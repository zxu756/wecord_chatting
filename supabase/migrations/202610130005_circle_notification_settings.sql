-- Per-circle notification settings for the current user. No row means the
-- default: notify for every channel message, not muted. Muting "until I turn
-- it back on" stores a timestamp 100 years ahead, like set_conversation_muted.
-- Rows go away with the circle membership.
create table if not exists public.circle_notification_settings (
  circle_id uuid not null,
  user_id uuid not null,
  level text not null default 'all',
  muted_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (circle_id, user_id),
  constraint circle_notification_settings_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade,
  constraint circle_notification_settings_level_check
    check (level in ('all', 'mentions', 'none'))
);

alter table public.circle_notification_settings enable row level security;

drop policy if exists circle_notification_settings_select_own on public.circle_notification_settings;
create policy circle_notification_settings_select_own
  on public.circle_notification_settings for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists circle_notification_settings_insert_own on public.circle_notification_settings;
create policy circle_notification_settings_insert_own
  on public.circle_notification_settings for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_current_user_circle_member(circle_id)
  );

drop policy if exists circle_notification_settings_update_own on public.circle_notification_settings;
create policy circle_notification_settings_update_own
  on public.circle_notification_settings for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists circle_notification_settings_delete_own on public.circle_notification_settings;
create policy circle_notification_settings_delete_own
  on public.circle_notification_settings for delete
  to authenticated
  using (user_id = auth.uid());

-- The current user's settings for a circle, defaulting to 'all' / unmuted.
create or replace function public.get_circle_notification_settings(
  target_circle_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  stored_level text;
  stored_muted_until timestamptz;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can read notification settings'
      using errcode = '42501';
  end if;

  select cns.level, cns.muted_until
  into stored_level, stored_muted_until
  from public.circle_notification_settings cns
  where cns.circle_id = target_circle_id
    and cns.user_id = current_user_id;

  return jsonb_build_object(
    'circle_id', target_circle_id,
    'level', coalesce(stored_level, 'all'),
    'muted_until', stored_muted_until
  );
end;
$$;

-- Saves the current user's settings for a circle. A null or past
-- muted_until unmutes. Returns the stored settings.
create or replace function public.set_circle_notification_settings(
  target_circle_id uuid,
  level text,
  muted_until timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_level text := lower(btrim(coalesce(level, '')));
  normalized_muted_until timestamptz := case
    when muted_until is not null and muted_until > now() then muted_until
    else null
  end;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_level not in ('all', 'mentions', 'none') then
    raise exception 'Notification level must be all, mentions or none'
      using errcode = '22023';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can change notification settings'
      using errcode = '42501';
  end if;

  insert into public.circle_notification_settings as cns (
    circle_id,
    user_id,
    level,
    muted_until,
    updated_at
  )
  values (
    target_circle_id,
    current_user_id,
    normalized_level,
    normalized_muted_until,
    now()
  )
  on conflict (circle_id, user_id) do update
  set level = excluded.level,
    muted_until = excluded.muted_until,
    updated_at = excluded.updated_at;

  return jsonb_build_object(
    'circle_id', target_circle_id,
    'level', normalized_level,
    'muted_until', normalized_muted_until
  );
end;
$$;

-- Same as 202605190004_group_announcement_polish, plus the circle a channel
-- conversation belongs to and the current user's notification settings for
-- that circle (null for direct and group conversations), so the local
-- notification coordinator can filter channel messages without extra calls.
drop function if exists public.list_conversation_summaries();

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  announcement_updated_at timestamptz,
  announcement_updated_by uuid,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[],
  circle_id uuid,
  circle_notification_level text,
  circle_muted_until timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with current_memberships as (
    select
      cm.conversation_id,
      cm.last_read_message_id,
      cm.pinned_at,
      cm.muted_until,
      cm.hidden_at,
      cm.manual_unread_at
    from public.conversation_members cm
    where cm.user_id = auth.uid()
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    group by mm.message_id
  )
  select
    c.id,
    c.type,
    coalesce(c.title, dp.display_name) as title,
    coalesce(c.avatar_url, dp.avatar_url) as avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    greatest(
      count(unread_messages.id),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids,
    cc.circle_id,
    case
      when cc.circle_id is null then null
      else coalesce(cns.level, 'all')
    end as circle_notification_level,
    cns.muted_until as circle_muted_until
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.circle_channels cc on cc.conversation_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join public.messages unread_messages
    on unread_messages.conversation_id = c.id
    and unread_messages.sender_id <> auth.uid()
    and (
      rm.last_read_at is null
      or unread_messages.created_at > rm.last_read_at
    )
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  group by
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.announcement,
    c.announcement_updated_at,
    c.announcement_updated_by,
    dp.display_name,
    dp.avatar_url,
    last_message.body,
    last_message.sender_id,
    last_message.recalled_at,
    last_message.type,
    c.last_message_at,
    c.updated_at,
    cm.pinned_at,
    cm.muted_until,
    cm.manual_unread_at,
    mc.member_count,
    lmm.mentioned_user_ids,
    cc.circle_id,
    cns.level,
    cns.muted_until
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

grant execute on function public.get_circle_notification_settings(uuid) to authenticated;
grant execute on function public.set_circle_notification_settings(uuid, text, timestamptz) to authenticated;
grant execute on function public.list_conversation_summaries() to authenticated;
