-- @here reaches the members the server knows are online.
--
-- Online state lived only in Realtime presence, so the sender's app said
-- who was online and record_message_mentions (202610160003) trusted that
-- list. Now @here is resolved from presence_heartbeats, the server-side
-- heartbeat of 202610160041_circle_discovery: visible, online clients call
-- touch_presence(true) about every two minutes and touch_presence(false)
-- when they stop, and Invisible or hidden users never have a row.
--
-- * A member counts as online for @here when their heartbeat is under 3
--   minutes old (one two-minute beat plus slack, so nobody flickers out
--   between beats) and their saved privacy settings don't hide them.
-- * The user_ids the sender's app still sends with {kind: 'here'} are
--   ignored (kept by the app for older servers).
-- * The table is created here too, exactly as 202610160041 does (if not
--   exists), so this migration works in either order; 202610160041 adds
--   touch_presence, which feeds it. Until that migration is applied,
--   nobody has a heartbeat and @here reaches nobody.

create table if not exists public.presence_heartbeats (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now()
);

create index if not exists presence_heartbeats_seen_idx
  on public.presence_heartbeats (seen_at desc);

alter table public.presence_heartbeats enable row level security;
revoke all on public.presence_heartbeats from anon, authenticated;

-- Same as 202610160003_role_and_here_mentions, but @here comes from
-- presence_heartbeats (see the header).
create or replace function public.record_message_mentions(
  target_message_id uuid,
  target_conversation_id uuid,
  sender_id uuid,
  requested_mentions jsonb,
  stored_mentions jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select
    target_message_id,
    target_conversation_id,
    (mention->>'user_id')::uuid,
    coalesce(nullif(mention->>'kind', ''), 'user')
  from jsonb_array_elements(stored_mentions) mention
  where coalesce(nullif(mention->>'kind', ''), 'user') in ('user', 'all')
    and (mention->>'user_id') is not null
  on conflict do nothing;

  -- @here: members the server saw online lately (presence_heartbeats),
  -- not the sender's list, which requested_mentions still carries for
  -- older servers.
  if exists (
    select 1
    from jsonb_array_elements(stored_mentions) mention
    where mention->>'kind' = 'here'
  ) then
    insert into public.message_mentions (
      message_id,
      conversation_id,
      user_id,
      kind
    )
    select
      target_message_id,
      target_conversation_id,
      cm.user_id,
      'here'
    from public.conversation_members cm
    join public.presence_heartbeats h on h.user_id = cm.user_id
    left join public.user_privacy_settings ups on ups.user_id = cm.user_id
    where cm.conversation_id = target_conversation_id
      and cm.user_id <> sender_id
      and h.seen_at > now() - interval '3 minutes'
      and coalesce(ups.presence_status, 'online') <> 'invisible'
      and coalesce(ups.show_online_status, true)
      and public.user_has_conversation_channel_permission(
        target_conversation_id,
        cm.user_id,
        'view_channel'
      )
    on conflict do nothing;
  end if;

  insert into public.message_mentions (
    message_id,
    conversation_id,
    user_id,
    kind
  )
  select distinct
    target_message_id,
    target_conversation_id,
    cm.user_id,
    'role'
  from jsonb_array_elements(stored_mentions) mention
  join public.circle_member_roles mr
    on mr.role_id = (mention->>'role_id')::uuid
  join public.conversation_members cm
    on cm.conversation_id = target_conversation_id
    and cm.user_id = mr.user_id
  where mention->>'kind' = 'role'
    and cm.user_id <> sender_id
    and public.user_has_conversation_channel_permission(
      target_conversation_id,
      cm.user_id,
      'view_channel'
    )
  on conflict do nothing;
end;
$$;

revoke execute on function public.record_message_mentions(uuid, uuid, uuid, jsonb, jsonb) from public, anon, authenticated;
