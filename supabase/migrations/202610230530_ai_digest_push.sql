-- Daily digest (F3), part 4 of 5: the push "Your daily digest is ready".
--
-- ai_digest_finish (202610230520) wakes the scheduled-dispatch function,
-- which calls claim_digest_pushes: one row per push subscription of the person
-- for each finished digest nobody has pushed yet, claimed once. The card
-- itself is list_my_ai_digests; this is only the push.
--
--   * worded in the subscription's language ('en' or 'zh') and tagged per
--     digest, opens Notifications;
--   * the title and body carry no chat content (a lock screen shows them):
--     only how many chats had news;
--   * a person in Do Not Disturb is not pushed (the card still waits); quiet
--     hours are applied by the function, as for every other push;
--   * a digest more than 15 minutes old when the function gets to it is
--     closed without a push, so a long outage does not end in a burst.

create or replace function public.claim_digest_pushes()
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
  update public.ai_digests d
  set push_claimed_at = now()
  where d.push_claimed_at is null
    and d.status = 'done'
    and d.finished_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.ai_digests d
    set push_claimed_at = now()
    where d.push_claimed_at is null
      and d.status = 'done'
    returning d.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then '今日速览已就绪' else 'Your daily digest is ready' end,
    case
      when s.language = 'zh' then
        jsonb_array_length(c.items)::text || ' 个聊天有新动态，点开看看。'
      when jsonb_array_length(c.items) = 1 then '1 chat has news. Open WeCord to catch up.'
      else jsonb_array_length(c.items)::text || ' chats have news. Open WeCord to catch up.'
    end,
    'ai-digest-' || c.id::text,
    '/#/notifications'
  from claimed c
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd';
end;
$$;

revoke execute on function public.claim_digest_pushes() from public, anon, authenticated;
grant execute on function public.claim_digest_pushes() to service_role;
