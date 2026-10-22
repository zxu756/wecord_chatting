-- Scheduled calls (roadmap E2), part 3 of 5: the reminder of an event with a
-- call says so, and opens the call.
--
-- claim_chat_event_reminder_pushes is rewritten from its newest definition,
-- 202610200010_push_text_language.sql (the "starts in" line per language; no
-- later migration redefines it). Everything it did stays: the 30 minute limit,
-- the chat's mute, the language of each device, `max_reminders`. New:
--
--   * a column call_link_code: the code of the event's call link while it
--     works, and only for a reminder about an event that starts within 20
--     minutes (the 1 hour reminder of an event with a call is not a "join
--     now"); otherwise null;
--   * the body of an event with a call ends with " · Tap to join the call"
--     (" · 点按加入通话") in that case, and " · Includes a call"
--     (" · 附带通话") for the earlier reminder.
--
-- Both senders (scheduled-dispatch and chat-event-reminders) open
-- /#/call/<code> when the row has a code, except for a chat the person locked
-- (G2), which opens the chat as before. A chat in quiet hours (A4) is held back
-- like every event reminder.
--
-- The return type changes, so the old function is dropped first; the
-- permissions are put back as they were (the service role only).

drop function if exists public.claim_chat_event_reminder_pushes(integer);

create or replace function public.claim_chat_event_reminder_pushes(
  max_reminders integer default 200
)
returns table (
  reminder_id uuid,
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  event_id uuid,
  title text,
  body text,
  call_link_code text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with claimed as (
    update public.chat_event_reminders r
    set push_sent_at = now()
    where r.id in (
      select p.id
      from public.chat_event_reminders p
      where p.push_sent_at is null
        and p.created_at > now() - interval '30 minutes'
      order by p.created_at
      limit greatest(1, least(coalesce(max_reminders, 200), 1000))
      for update skip locked
    )
    returning r.id, r.event_id, r.user_id, r.lead_minutes
  ),
  rows_with_call as (
    select
      claimed.id as claimed_id,
      claimed.event_id as claimed_event_id,
      claimed.user_id as claimed_user_id,
      claimed.lead_minutes as claimed_lead,
      public.scheduled_call_code(e.call_link_code) as working_code,
      e.starts_at <= now() + interval '20 minutes' as near
    from claimed
    join public.chat_events e on e.id = claimed.event_id
  )
  select
    rc.claimed_id,
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    e.conversation_id,
    e.id,
    e.title,
    case
      when s.language = 'zh' then
        case
          when e.starts_at <= now() then '现在开始'
          when rc.claimed_lead >= 60 then '约 1 小时后开始'
          else greatest(1, ceil(extract(epoch from (e.starts_at - now())) / 60)::integer) || ' 分钟后开始'
        end
        || case
          when rc.working_code is null then ''
          when rc.near then ' · 点按加入通话'
          else ' · 附带通话'
        end
      else
        case
          when e.starts_at <= now() then 'Starting now'
          when rc.claimed_lead >= 60 then 'Starts in about 1 hour'
          else 'Starts in ' || greatest(1, ceil(extract(epoch from (e.starts_at - now())) / 60)::integer) || ' minutes'
        end
        || case
          when rc.working_code is null then ''
          when rc.near then ' · Tap to join the call'
          else ' · Includes a call'
        end
    end,
    case when rc.near then rc.working_code end
  from rows_with_call rc
  join public.chat_events e on e.id = rc.claimed_event_id
  join public.conversation_members cm
    on cm.conversation_id = e.conversation_id and cm.user_id = rc.claimed_user_id
  join public.push_subscriptions s on s.user_id = rc.claimed_user_id
  where e.cancelled_at is null
    and (cm.muted_until is null or cm.muted_until < now());
end;
$$;

revoke execute on function public.claim_chat_event_reminder_pushes(integer)
  from public, anon, authenticated;
grant execute on function public.claim_chat_event_reminder_pushes(integer)
  to service_role;
