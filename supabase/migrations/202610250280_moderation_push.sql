-- Moderator tools 2.0 / raid protection (C5, C6), part 9 of 9: the pushes.
--
-- Two kinds, one claim function for scheduled-dispatch (it is woken by
-- decide_ban_appeal and by an automatic lockdown):
--
--   * "Raid protection locked <circle>": to the devices of the circle's
--     moderators (the owner, and members with kick_members or manage_circle
--     through a role) when the check locked the circle down by itself
--     (circle_raid_events source 'auto'). It opens the circle, where the
--     Review page holds the one-tap "End lockdown".
--   * "Your ban appeal was approved / declined": to the devices of the person
--     who appealed (circle_ban_appeals decided as approved or denied). It
--     opens Notifications, where the card with the moderators' note waits.
--
-- Each is claimed once; one older than 15 minutes when the function gets to it
-- is closed without a push, so a long outage does not end in a burst. Each
-- push is worded in its subscription's language ('en' or 'zh'). Names are
-- cleaned of angle brackets, so they cannot pass for a time token.

create or replace function public.claim_moderation_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  update public.circle_raid_events e
  set push_claimed_at = now()
  where e.push_claimed_at is null
    and e.kind = 'lockdown'
    and e.source = 'auto'
    and e.created_at <= now() - interval '15 minutes';

  update public.circle_ban_appeals a
  set push_claimed_at = now()
  where a.push_claimed_at is null
    and a.status in ('approved', 'denied')
    and a.decided_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.circle_raid_events e
    set push_claimed_at = now()
    where e.push_claimed_at is null
      and e.kind = 'lockdown'
      and e.source = 'auto'
    returning e.*
  ),
  claimed_appeals as (
    update public.circle_ban_appeals u
    set push_claimed_at = now()
    where u.push_claimed_at is null
      and u.status in ('approved', 'denied')
    returning u.*
  ),
  named as (
    select
      c.id as event_id,
      c.circle_id,
      c.joins,
      btrim(replace(replace(ci.name, '<', ''), '>', '')) as circle_name
    from claimed c
    join public.circles ci on ci.id = c.circle_id
  ),
  recipients as (
    select n.event_id, n.circle_id, n.joins, n.circle_name, cm.user_id
    from named n
    join public.circle_members cm on cm.circle_id = n.circle_id
    where exists (
        select 1 from public.circles ci
        where ci.id = n.circle_id and ci.owner_id = cm.user_id
      )
      or (
        exists (
          select 1 from public.circle_member_roles mr
          where mr.circle_id = n.circle_id and mr.user_id = cm.user_id
        )
        and (
          public.circle_member_has_permission(n.circle_id, cm.user_id, 'kick_members')
          or public.circle_member_has_permission(n.circle_id, cm.user_id, 'manage_circle')
        )
      )
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then '突袭防护已启动' else 'Raid protection is on' end,
    case
      when s.language = 'zh' then
        '「' || r.circle_name || '」短时间内有 ' || coalesce(r.joins, 0)
          || ' 人加入或申请加入，已暂停邀请并改为申请入圈。打开 WeCord 查看，可一键解除。'
      else
        r.circle_name || ' had ' || coalesce(r.joins, 0)
          || ' people join or ask to join in a few minutes. Invites are paused and joining needs approval. Open WeCord to review, or end the lockdown.'
    end,
    'raid-' || r.event_id::text,
    '/#/circles/' || r.circle_id::text
  from recipients r
  join public.push_subscriptions s on s.user_id = r.user_id
  union all
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case
      when d.status = 'approved' and s.language = 'zh' then '封禁申诉已通过'
      when d.status = 'approved' then 'Ban appeal approved'
      when s.language = 'zh' then '封禁申诉未通过'
      else 'Ban appeal declined'
    end,
    case
      when d.status = 'approved' and s.language = 'zh' then
        '「' || d.circle_name || '」解除了你的封禁。'
      when d.status = 'approved' then
        d.circle_name || ' lifted your ban.'
      when s.language = 'zh' then
        '「' || d.circle_name || '」没有通过你的申诉。' || coalesce('理由：' || d.note, '')
      else
        d.circle_name || ' declined your appeal.' || coalesce(' Reason: ' || d.note, '')
    end,
    'ban-appeal-' || d.id::text,
    '/#/notifications'
  from (
    select
      a.id,
      a.user_id,
      a.status,
      btrim(replace(replace(ci.name, '<', ''), '>', '')) as circle_name,
      nullif(btrim(replace(replace(coalesce(a.note, ''), '<', ''), '>', '')), '') as note
    from claimed_appeals a
    join public.circles ci on ci.id = a.circle_id
  ) d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_moderation_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_moderation_pushes() to service_role;
