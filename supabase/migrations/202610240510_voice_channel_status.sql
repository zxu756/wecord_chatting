-- Voice channel status (E6): one line, like "playing ranked", that people in
-- a voice channel can set and everyone who can see the channel reads in the
-- channel list.
--
-- * circle_channels.voice_status: null or 1 to 60 characters, one line.
-- * set_voice_channel_status(channel_id, status): needs a live voice state in
--   that channel (the person is in it right now) and connect_voice. Blank
--   clears it. Runs of white space (line breaks included) become one space.
-- * list_voice_channel_statuses(circle_id): {channel id: status} for the
--   channels the caller can see that have somebody in them right now. A
--   status left in an empty channel is not shown.
-- * The first person to join an empty channel clears the old status (a
--   reconnect of the same person does not: joined_at is kept then).
-- get_circle_detail is not rewritten; the list is a separate call, like
-- list_voice_channel_user_limits (202610160004).

alter table public.circle_channels
  add column if not exists voice_status text;

alter table public.circle_channels
  drop constraint if exists circle_channels_voice_status_length;
alter table public.circle_channels
  add constraint circle_channels_voice_status_length check (
    voice_status is null
    or (
      voice_status = btrim(voice_status)
      and char_length(voice_status) between 1 and 60
      and voice_status !~ '[\r\n\t]'
    )
  );

create or replace function public.set_voice_channel_status(
  target_channel_id uuid,
  new_status text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  cleaned text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null or channel.kind <> 'voice' then
    raise exception 'Voice channel not found' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.voice_states vs
    where vs.channel_id = channel.id
      and vs.user_id = current_user_id
      and vs.last_seen_at > now() - public.voice_state_ttl()
  ) or not public.current_user_has_channel_permission(
    channel.id,
    'connect_voice'
  ) then
    raise exception 'Only people in the voice channel can set its status'
      using errcode = '42501';
  end if;

  cleaned := nullif(
    btrim(regexp_replace(coalesce(new_status, ''), '\s+', ' ', 'g')),
    ''
  );
  if cleaned is not null and char_length(cleaned) > 60 then
    raise exception 'A status is at most 60 characters' using errcode = '22023';
  end if;

  update public.circle_channels cc
  set voice_status = cleaned
  where cc.id = channel.id
    and cc.voice_status is distinct from cleaned;

  return cleaned;
end;
$$;

create or replace function public.list_voice_channel_statuses(
  target_circle_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_object_agg(cc.id::text, cc.voice_status)
    from public.circle_channels cc
    where cc.circle_id = target_circle_id
      and cc.kind = 'voice'
      and cc.voice_status is not null
      and public.current_user_has_channel_permission(cc.id, 'view_channel')
      and exists (
        select 1
        from public.voice_states vs
        where vs.channel_id = cc.id
          and vs.last_seen_at > now() - public.voice_state_ttl()
      )
  ), '{}'::jsonb);
end;
$$;

-- A fresh join into a channel nobody else is in starts without the old
-- status.
create or replace function public.voice_states_clear_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.joined_at >= now() - interval '5 seconds'
    and not exists (
      select 1
      from public.voice_states vs
      where vs.channel_id = new.channel_id
        and vs.user_id <> new.user_id
        and vs.last_seen_at > now() - public.voice_state_ttl()
    )
  then
    update public.circle_channels cc
    set voice_status = null
    where cc.id = new.channel_id
      and cc.voice_status is not null;
  end if;
  return new;
end;
$$;

drop trigger if exists voice_states_clear_status on public.voice_states;
create trigger voice_states_clear_status
  after insert on public.voice_states
  for each row execute function public.voice_states_clear_status();

revoke execute on function public.set_voice_channel_status(uuid, text) from public, anon;
revoke execute on function public.list_voice_channel_statuses(uuid) from public, anon;
revoke execute on function public.voice_states_clear_status() from public, anon, authenticated;
grant execute on function public.set_voice_channel_status(uuid, text) to authenticated;
grant execute on function public.list_voice_channel_statuses(uuid) to authenticated;
