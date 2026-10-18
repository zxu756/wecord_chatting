-- Circle join requests (C1), part 4 of 4: the push that tells the applicant.
--
-- decide_join_request (202610220620) wakes the scheduled-dispatch function,
-- which calls claim_join_request_pushes: one row per push subscription of the
-- applicant for each decision nobody has pushed yet, claimed once. The
-- notification itself (the card in Notifications) is
-- list_my_join_requests; this is only the push.
--
-- Each push is worded in its subscription's language ('en' or 'zh') with the
-- time as a time token that the function writes in the subscription's time
-- zone (the same <t:unix:f> tokens the login alerts use). A decision older
-- than 15 minutes when the function gets to it is closed without a push, so a
-- long outage does not end in a burst. Approved opens the circle (where the
-- rules and the welcome message wait); denied opens Notifications.
--
-- The names of the circle and the note are cleaned of angle brackets, so they
-- cannot pass for a time token.

create or replace function public.claim_join_request_pushes()
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
  update public.circle_join_requests r
  set push_claimed_at = now()
  where r.push_claimed_at is null
    and r.status <> 'pending'
    and r.decided_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.circle_join_requests r
    set push_claimed_at = now()
    where r.push_claimed_at is null
      and r.status <> 'pending'
    returning r.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case
      when c.status = 'approved' and s.language = 'zh' then '入圈申请已通过'
      when c.status = 'approved' then 'Join request approved'
      when s.language = 'zh' then '入圈申请未通过'
      else 'Join request declined'
    end,
    case
      when c.status = 'approved' and s.language = 'zh' then
        '「' || label.circle_name || '」通过了你的申请，<t:'
          || floor(extract(epoch from c.decided_at))::bigint
          || ':f>。打开 WeCord 阅读规则并打个招呼。'
      when c.status = 'approved' then
        'You are in ' || label.circle_name || ', <t:'
          || floor(extract(epoch from c.decided_at))::bigint
          || ':f>. Open WeCord to read the rules and say hello.'
      when s.language = 'zh' then
        '「' || label.circle_name || '」没有通过你的申请，<t:'
          || floor(extract(epoch from c.decided_at))::bigint
          || ':f>。'
          || coalesce('理由：' || label.note, '')
      else
        label.circle_name || ' declined your request, <t:'
          || floor(extract(epoch from c.decided_at))::bigint
          || ':f>.'
          || coalesce(' Reason: ' || label.note, '')
    end,
    'join-request-' || c.id::text,
    case
      when c.status = 'approved' then '/#/circles/' || c.circle_id::text
      else '/#/notifications'
    end
  from claimed c
  cross join lateral (
    select
      btrim(replace(replace(
        (select ci.name from public.circles ci where ci.id = c.circle_id),
        '<', ''), '>', '')) as circle_name,
      nullif(btrim(replace(replace(coalesce(c.note, ''), '<', ''), '>', '')), '') as note
  ) label
  join public.push_subscriptions s
    on s.user_id = c.user_id;
end;
$$;

revoke execute on function public.claim_join_request_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_join_request_pushes() to service_role;
