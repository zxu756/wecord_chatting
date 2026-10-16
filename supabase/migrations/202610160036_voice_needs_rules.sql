-- Voice tokens wait for the circle's rules.
--
-- can_current_user_connect_voice, which the livekit-token Edge Function
-- asks before minting a token, now refuses (null, so 403) members who
-- have not accepted the circle's rules while onboarding is on, like the
-- voice_states trigger of 202610160021 already does. The owner and
-- members with manage_circle are exempt (circle_member_needs_rules).

-- Same as 202610160018_stage_channels, plus the rules check.
create or replace function public.can_current_user_connect_voice(
  target_channel_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  member public.circle_members%rowtype;
begin
  if auth.uid() is null then
    return null;
  end if;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or channel.kind not in ('voice', 'stage')
    or not public.current_user_has_channel_permission(
      channel.id,
      'connect_voice'
    )
  then
    return null;
  end if;

  -- Onboarding (202610160021): members who still have to accept the
  -- circle's rules get no voice token; the owner and members with
  -- manage_circle never have to.
  if public.circle_member_needs_rules(channel.circle_id, auth.uid()) then
    return null;
  end if;

  select cm.*
  into member
  from public.circle_members cm
  where cm.circle_id = channel.circle_id
    and cm.user_id = auth.uid();

  return jsonb_build_object(
    'channel_id', channel.id,
    'channel_name', channel.name,
    'circle_id', channel.circle_id,
    'display_name', (
      select coalesce(
        nullif(trim(cm.nickname), ''),
        nullif(trim(p.display_name), ''),
        p.username
      )
      from public.profiles p
      left join public.circle_members cm
        on cm.circle_id = channel.circle_id
        and cm.user_id = p.id
      where p.id = auth.uid()
    ),
    'full', public.voice_channel_is_full_for_current_user(channel.id),
    'server_mute', coalesce(member.voice_server_mute, false),
    'server_deaf', coalesce(member.voice_server_deaf, false),
    'kind', channel.kind,
    'stage_speaker', channel.kind = 'stage' and exists (
      select 1
      from public.voice_states vs
      where vs.channel_id = channel.id
        and vs.user_id = auth.uid()
        and vs.stage_speaker
        and vs.last_seen_at > now() - public.voice_state_ttl()
    )
  );
end;
$$;

revoke execute on function public.can_current_user_connect_voice(uuid) from public, anon;
grant execute on function public.can_current_user_connect_voice(uuid) to authenticated;
