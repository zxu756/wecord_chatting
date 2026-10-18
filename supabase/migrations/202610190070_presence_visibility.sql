-- Who may see that a person is online: only people who share something
-- with them. Replaces the global "online-users" presence channel.
--
-- The problem. Everybody tracked themselves on ONE private presence channel,
-- "online-users" (202610190050_realtime_private.sql), and any signed-in
-- account could join it and read the id and status (online, idle, dnd) of
-- every online user, blocked or not. "Show when you are online" was honoured
-- by the client only.
--
-- The design: the server decides, the channel only nudges.
--
--   * presence_state          who has the app open and visible right now
--                             (seen_at, refreshed by touch_presence about
--                             every two minutes) and whether they are away
--                             from the keyboard. Nobody can read it.
--   * visible_presence(ids)   THE way to read it: the people the caller may
--                             see, who are online, with their status. Rules
--                             (presence_contacts / presence_can_see):
--                               - friends,
--                               - members of a circle they are both in,
--                               - members of a group or direct chat they
--                                 are both in,
--                               - and never when either of the two blocked
--                                 the other.
--                             Hidden people are left out by the server, on
--                             every read: Invisible, or "Show when you are
--                             online" off. Do Not Disturb and Idle (picked)
--                             come from the person's saved settings, never
--                             from what a client claims; a client can only
--                             say "I am away from the keyboard", which turns
--                             Online into Idle.
--   * presence-updates:<viewer id>
--                             a private BROADCAST channel of the viewer's
--                             own (like moments:<user id>, 202610190020).
--                             Events: "changed" {"user_ids": [...]} (these
--                             people came, went or changed: read them again
--                             with visible_presence(ids)) and "reset" {}
--                             (read everything again). A signal carries only
--                             ids, never a status, and is sent only to
--                             viewers who may see the person at that moment,
--                             and who have the app open. Nobody can send on
--                             it (no insert policy); the database writes it
--                             through realtime.send as the function owner.
--
-- Why not the other options.
--   (a) one presence topic per user: a viewer joins one channel per friend
--       and circle mate (hundreds to thousands), every join runs the policy,
--       and a relationship change (block, kicked from a circle) must
--       re-authorize every joined channel. The policy would have to answer
--       "do these two share a circle" on every join and every token refresh.
--   (c) per circle / per chat presence channels: a person in 30 circles and
--       200 chats tracks on 230 channels; friends have no shared scope at
--       all; and "show online = off" or a block can not be applied per
--       viewer inside a shared channel (everybody in it sees every tracked
--       payload).
--   Server side keeps one channel per viewer and one query per refresh, and
--   all rules live in one place that SQL tests can cover.
--
-- Latency. A person coming, going or changing status is told to their
-- online viewers in the same transaction (touch_presence, set_presence_status,
-- set_show_online_status); the viewer's app batches the ids for half a second
-- and reads them with one RPC. So a change shows within about a second. A
-- client that vanishes without saying goodbye (a crash, a closed laptop)
-- is shown offline once its last beat is three minutes old; the app reads
-- everything again every minute and when it returns to the foreground, which
-- also heals a missed signal.
--
-- Cost. A change costs one realtime.send per ONLINE person who may see the
-- changed one (offline people read everything when they open the app), at
-- most 1000 per change (the rest catch up with their next read, at most a
-- minute later). Refreshing a heartbeat sends nothing. Each viewer makes one
-- visible_presence call a minute, plus one per burst of changes.
--
-- Relationship changes (befriend, unfriend, block, unblock, join or leave a
-- circle or chat) signal the people concerned the same way, so an ex-member
-- stops seeing the person at once instead of at the next read.
--
-- Old apps keep working: touch_presence still takes just is_online, they
-- keep beating (so new apps see them) and, once 202610190071 removes the
-- online-users policies, they join nothing and see nobody online.
--
-- Deploy order: this migration, then the apps, then 202610190071.

-- ------------------------------------------------------------------ state

create table if not exists public.presence_state (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now(),
  -- The client says the person is away from the keyboard.
  away boolean not null default false
);

create index if not exists presence_state_seen_idx
  on public.presence_state (seen_at desc);

alter table public.presence_state enable row level security;
revoke all on public.presence_state from anon, authenticated;

-- How long after its last beat a client still counts as here. One beat every
-- two minutes, plus slack so nobody flickers out between beats.
create or replace function public.presence_window()
returns interval
language sql
immutable
as $$ select interval '3 minutes' $$;

-- What others see for a person with these settings: online, idle, dnd, or
-- null when they are hidden (Invisible, or the switch is off). [away] only
-- turns Online into Idle.
create or replace function public.presence_effective(
  saved_status text,
  show_online boolean,
  away boolean
)
returns text
language sql
immutable
as $$
  select case
    when not coalesce(show_online, true) then null
    when coalesce(saved_status, 'online') = 'invisible' then null
    when saved_status in ('dnd', 'idle') then saved_status
    when coalesce(away, false) then 'idle'
    else 'online'
  end;
$$;

-- ----------------------------------------------------------- relationships

-- Whether [viewer] may see [target]'s presence: they share a friendship, a
-- circle, or a group or direct chat, and neither blocked the other. Does not
-- look at the target's own settings. Internal.
create or replace function public.presence_can_see(viewer uuid, target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select viewer is not null
    and target is not null
    and viewer <> target
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = viewer and b.blocked_id = target)
         or (b.blocker_id = target and b.blocked_id = viewer)
    )
    and (
      exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(viewer, target)
          and f.user_high_id = greatest(viewer, target)
      )
      or exists (
        select 1
        from public.circle_members a
        join public.circle_members b on b.circle_id = a.circle_id
        where a.user_id = viewer
          and b.user_id = target
      )
      or exists (
        select 1
        from public.conversation_members a
        join public.conversation_members b
          on b.conversation_id = a.conversation_id
        join public.conversations c on c.id = a.conversation_id
        where a.user_id = viewer
          and b.user_id = target
          and c.type in ('direct', 'group')
      )
    );
$$;

-- Everyone [who] may see, whatever their settings: friends, circle mates,
-- chat mates, minus blocks in either direction. Symmetric: x is in
-- presence_contacts(y) exactly when y is in presence_contacts(x). Internal.
create or replace function public.presence_contacts(who uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select t.id
  from (
    select case when f.user_low_id = who then f.user_high_id else f.user_low_id end as id
    from public.friendships f
    where f.user_low_id = who or f.user_high_id = who
    union
    select b.user_id
    from public.circle_members a
    join public.circle_members b on b.circle_id = a.circle_id
    where a.user_id = who
    union
    select b.user_id
    from public.conversation_members a
    join public.conversations c
      on c.id = a.conversation_id and c.type in ('direct', 'group')
    join public.conversation_members b on b.conversation_id = a.conversation_id
    where a.user_id = who
  ) t
  where t.id <> who
    and not exists (
      select 1
      from public.blocks k
      where (k.blocker_id = who and k.blocked_id = t.id)
         or (k.blocker_id = t.id and k.blocked_id = who)
    );
$$;

-- ----------------------------------------------------------------- reading

-- The people the caller may see who are online, with their status
-- ('online', 'idle' or 'dnd'). With [target_ids] (at most 200), only those.
create or replace function public.visible_presence(target_ids uuid[] default null)
returns table (user_id uuid, status text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer uuid := auth.uid();
begin
  if viewer is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_ids is not null then
    if coalesce(array_length(target_ids, 1), 0) > 200 then
      raise exception 'Too many people' using errcode = '22023';
    end if;
    return query
    select s.user_id, e.status
    from unnest(target_ids) as wanted(id)
    join public.presence_state s on s.user_id = wanted.id
    left join public.user_privacy_settings ups on ups.user_id = s.user_id
    cross join lateral (
      select public.presence_effective(
        ups.presence_status, ups.show_online_status, s.away
      ) as status
    ) e
    where s.seen_at > now() - public.presence_window()
      and e.status is not null
      and public.presence_can_see(viewer, s.user_id);
    return;
  end if;

  return query
  select s.user_id, e.status
  from public.presence_contacts(viewer) as contact(id)
  join public.presence_state s on s.user_id = contact.id
  left join public.user_privacy_settings ups on ups.user_id = s.user_id
  cross join lateral (
    select public.presence_effective(
      ups.presence_status, ups.show_online_status, s.away
    ) as status
  ) e
  where s.seen_at > now() - public.presence_window()
    and e.status is not null
  limit 5000;
end;
$$;

-- --------------------------------------------------------------- signalling

-- Who may listen: a signed-in person, on their own topic, to receive only.
drop policy if exists presence_updates_receive_own on realtime.messages;
create policy presence_updates_receive_own
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'presence-updates:' || (select auth.uid())::text
  );

-- One signal. A courtesy: a Realtime failure never fails the caller. Internal.
create or replace function public.presence_send(
  recipient uuid,
  event_name text,
  ids jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if recipient is null then
    return;
  end if;
  begin
    perform realtime.send(
      jsonb_build_object('user_ids', coalesce(ids, '[]'::jsonb)),
      event_name,
      'presence-updates:' || recipient::text,
      true
    );
  exception when others then
    null;
  end;
end;
$$;

-- Whether [who] has the app open (and so listens for signals). Internal.
create or replace function public.presence_is_listening(who uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.presence_state s
    where s.user_id = who
      and s.seen_at > now() - public.presence_window()
  );
$$;

-- Tells [target]'s online viewers that [target] came, went or changed.
-- Internal.
create or replace function public.presence_notify(target uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer uuid;
begin
  for viewer in
    select contact.id
    from public.presence_contacts(target) as contact(id)
    join public.presence_state s on s.user_id = contact.id
    where s.seen_at > now() - public.presence_window()
    order by s.seen_at desc
    limit 1000
  loop
    perform public.presence_send(viewer, 'changed', jsonb_build_array(target));
  end loop;
end;
$$;

-- A relationship between two people appeared or went (friend, block): each
-- of them reads the other again. Internal.
create or replace function public.presence_pair_changed(a uuid, b uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.presence_is_listening(a) then
    perform public.presence_send(a, 'changed', jsonb_build_array(b));
  end if;
  if public.presence_is_listening(b) then
    perform public.presence_send(b, 'changed', jsonb_build_array(a));
  end if;
end;
$$;

-- [who] joined or left a circle or chat whose members are [members]: they
-- read everything again, and the members read them again. Internal.
create or replace function public.presence_scope_changed(
  who uuid,
  members uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  member uuid;
begin
  if not public.presence_is_listening(who) then
    -- Nobody can see them, and they have the app closed: they read
    -- everything when they open it.
    return;
  end if;
  perform public.presence_send(who, 'reset', '[]'::jsonb);
  foreach member in array coalesce(members, '{}') loop
    perform public.presence_send(member, 'changed', jsonb_build_array(who));
  end loop;
end;
$$;

create or replace function public.presence_friendship_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.presence_pair_changed(old.user_low_id, old.user_high_id);
    return old;
  end if;
  perform public.presence_pair_changed(new.user_low_id, new.user_high_id);
  return new;
end;
$$;

create or replace function public.presence_block_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.presence_pair_changed(old.blocker_id, old.blocked_id);
    return old;
  end if;
  perform public.presence_pair_changed(new.blocker_id, new.blocked_id);
  return new;
end;
$$;

create or replace function public.presence_circle_member_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  who uuid;
  target_circle uuid;
  members uuid[];
begin
  if tg_op = 'DELETE' then
    who := old.user_id;
    target_circle := old.circle_id;
  else
    who := new.user_id;
    target_circle := new.circle_id;
  end if;
  -- A circle or an account going away takes its members with it: nobody is
  -- told one by one.
  if tg_op = 'DELETE'
    and (
      not exists (select 1 from public.circles c where c.id = target_circle)
      or not exists (select 1 from public.profiles p where p.id = who)
    )
  then
    return old;
  end if;
  select coalesce(array_agg(m.user_id), '{}') into members
  from (
    select cm.user_id
    from public.circle_members cm
    join public.presence_state s on s.user_id = cm.user_id
    where cm.circle_id = target_circle
      and cm.user_id <> who
      and s.seen_at > now() - public.presence_window()
    order by s.seen_at desc
    limit 1000
  ) m;
  perform public.presence_scope_changed(who, members);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.presence_conversation_member_changed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  who uuid;
  target_conversation uuid;
  members uuid[];
begin
  if tg_op = 'DELETE' then
    who := old.user_id;
    target_conversation := old.conversation_id;
  else
    who := new.user_id;
    target_conversation := new.conversation_id;
  end if;
  -- Only group and direct chats count (circle channels follow the circle),
  -- and a chat or an account going away is not signalled member by member.
  if not exists (
      select 1
      from public.conversations c
      where c.id = target_conversation and c.type in ('direct', 'group')
    )
    or not exists (select 1 from public.profiles p where p.id = who)
  then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;
  select coalesce(array_agg(m.user_id), '{}') into members
  from (
    select cm.user_id
    from public.conversation_members cm
    join public.presence_state s on s.user_id = cm.user_id
    where cm.conversation_id = target_conversation
      and cm.user_id <> who
      and s.seen_at > now() - public.presence_window()
    order by s.seen_at desc
    limit 1000
  ) m;
  perform public.presence_scope_changed(who, members);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists friendships_presence_signal on public.friendships;
create trigger friendships_presence_signal
  after insert or delete on public.friendships
  for each row execute function public.presence_friendship_changed();

drop trigger if exists blocks_presence_signal on public.blocks;
create trigger blocks_presence_signal
  after insert or delete on public.blocks
  for each row execute function public.presence_block_changed();

drop trigger if exists circle_members_presence_signal on public.circle_members;
create trigger circle_members_presence_signal
  after insert or delete on public.circle_members
  for each row execute function public.presence_circle_member_changed();

drop trigger if exists conversation_members_presence_signal on public.conversation_members;
create trigger conversation_members_presence_signal
  after insert or delete on public.conversation_members
  for each row execute function public.presence_conversation_member_changed();

-- --------------------------------------------------------------- the beat

-- The old touch_presence(is_online) is replaced by one with an optional
-- second argument; a call with just is_online (older apps) still works.
drop function if exists public.touch_presence(boolean);

-- Same as 202610160041_circle_discovery (presence_heartbeats, which discovery
-- and @here count), and in addition:
--   * presence_state is kept for everyone who has the app open and visible,
--     hidden or not (a hidden person still watches others), and removed when
--     the client says it is leaving;
--   * [shown_status] is what the client shows for itself; only 'idle' (away
--     from the keyboard) is taken from it, the rest comes from the saved
--     settings;
--   * when the person's visible status changed (came online, went, idle,
--     online again), their online viewers are signalled.
create or replace function public.touch_presence(
  is_online boolean default true,
  shown_status text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  settings public.user_privacy_settings%rowtype;
  old_state public.presence_state%rowtype;
  old_shown text;
  new_shown text;
  new_away boolean := coalesce(shown_status = 'idle', false);
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select s.* into settings
  from public.user_privacy_settings s
  where s.user_id = current_user_id;

  -- Discovery and @here: only people who can be seen count.
  if not coalesce(is_online, false)
    or coalesce(settings.presence_status, 'online') = 'invisible'
    or not coalesce(settings.show_online_status, true)
  then
    delete from public.presence_heartbeats h where h.user_id = current_user_id;
  else
    insert into public.presence_heartbeats as h (user_id, seen_at)
    values (current_user_id, now())
    on conflict (user_id) do update
      set seen_at = excluded.seen_at
      -- Several tabs or devices: one write every 30 seconds is enough.
      where h.seen_at < now() - interval '30 seconds';
  end if;

  select s.* into old_state
  from public.presence_state s
  where s.user_id = current_user_id
  for update;

  old_shown := case
    when old_state.user_id is not null
      and old_state.seen_at > now() - public.presence_window()
    then public.presence_effective(
      settings.presence_status, settings.show_online_status, old_state.away
    )
  end;

  if not coalesce(is_online, false) then
    delete from public.presence_state s where s.user_id = current_user_id;
    new_shown := null;
  else
    insert into public.presence_state as s (user_id, seen_at, away)
    values (current_user_id, now(), new_away)
    on conflict (user_id) do update
      set seen_at = excluded.seen_at, away = excluded.away
      where s.seen_at < now() - interval '30 seconds'
        or s.away is distinct from excluded.away;
    new_shown := public.presence_effective(
      settings.presence_status, settings.show_online_status, new_away
    );
  end if;

  if old_shown is distinct from new_shown then
    perform public.presence_notify(current_user_id);
  end if;
end;
$$;

-- Same as 202610160001_presence_statuses, and the person's online viewers
-- are told.
create or replace function public.set_presence_status(new_status text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if new_status is null
    or new_status not in ('online', 'idle', 'dnd', 'invisible')
  then
    raise exception 'Unknown status' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings (user_id, presence_status)
  values (auth.uid(), new_status)
  on conflict (user_id) do update
  set presence_status = excluded.presence_status;

  if public.presence_is_listening(auth.uid()) then
    perform public.presence_notify(auth.uid());
  end if;

  return new_status;
end;
$$;

create or replace function public.set_show_online_status(show boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if show is null then
    raise exception 'A value is required' using errcode = '22023';
  end if;

  insert into public.user_privacy_settings (user_id, show_online_status)
  values (auth.uid(), show)
  on conflict (user_id) do update
  set show_online_status = excluded.show_online_status;

  if public.presence_is_listening(auth.uid()) then
    perform public.presence_notify(auth.uid());
  end if;

  return show;
end;
$$;

-- ------------------------------------------------------------------ grants

revoke execute on function public.presence_window() from public, anon, authenticated;
revoke execute on function public.presence_effective(text, boolean, boolean) from public, anon, authenticated;
revoke execute on function public.presence_can_see(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.presence_contacts(uuid) from public, anon, authenticated;
revoke execute on function public.presence_send(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.presence_is_listening(uuid) from public, anon, authenticated;
revoke execute on function public.presence_notify(uuid) from public, anon, authenticated;
revoke execute on function public.presence_pair_changed(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.presence_scope_changed(uuid, uuid[]) from public, anon, authenticated;
revoke execute on function public.presence_friendship_changed() from public, anon, authenticated;
revoke execute on function public.presence_block_changed() from public, anon, authenticated;
revoke execute on function public.presence_circle_member_changed() from public, anon, authenticated;
revoke execute on function public.presence_conversation_member_changed() from public, anon, authenticated;

revoke execute on function public.visible_presence(uuid[]) from public, anon;
revoke execute on function public.touch_presence(boolean, text) from public, anon;
grant execute on function public.visible_presence(uuid[]) to authenticated;
grant execute on function public.touch_presence(boolean, text) to authenticated;
