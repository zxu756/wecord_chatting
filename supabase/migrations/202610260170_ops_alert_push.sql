-- Monitoring and alerts (K3), part 4 of 4: the push for an alert.
--
-- claim_ops_alert_pushes() is for the scheduled-dispatch function (service
-- role): a new alert with severity 'fail' wakes it (ops_raise_alert), and it
-- takes the devices of the owners and moderators here. Only failures are
-- pushed; a warning is a card in Notifications and a line in the console.
-- Each alert is pushed once, and at most 5 alerts are pushed in any hour, so
-- a night of trouble does not become a stream. An alert that is already
-- closed is not pushed. The text is the alert's own, in the language of
-- each device (title_zh/body_zh for 'zh', the English one otherwise, and
-- the other language when one is empty); angle brackets are removed so it
-- cannot pass for a time token. Tapping it opens the admin console.

create or replace function public.claim_ops_alert_pushes()
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
declare
  budget integer;
begin
  select greatest(5 - count(*), 0)::integer into budget
  from public.ops_alerts a
  where a.severity = 'fail'
    and a.push_claimed_at > now() - interval '1 hour';

  return query
  with claimed as (
    update public.ops_alerts a
    set push_claimed_at = now()
    where a.id in (
      select x.id
      from public.ops_alerts x
      where x.severity = 'fail'
        and x.resolved_at is null
        and x.push_claimed_at is null
      order by x.opened_at
      limit budget
    )
    returning a.id, a.title_en, a.title_zh, a.body_en, a.body_zh
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    left(replace(replace(
      case when s.language = 'zh'
        then coalesce(nullif(btrim(c.title_zh), ''), btrim(c.title_en))
        else coalesce(nullif(btrim(c.title_en), ''), btrim(c.title_zh))
      end, '<', ''), '>', ''), 80),
    left(replace(replace(
      case when s.language = 'zh'
        then coalesce(nullif(btrim(c.body_zh), ''), btrim(c.body_en))
        else coalesce(nullif(btrim(c.body_en), ''), btrim(c.body_zh))
      end, '<', ''), '>', ''), 180),
    'ops-alert-' || c.id::text,
    '/#/admin'
  from claimed c
  cross join public.app_admins ad
  join public.push_subscriptions s on s.user_id = ad.user_id
  where ad.role in ('owner', 'moderator');
end;
$$;

revoke execute on function public.claim_ops_alert_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_ops_alert_pushes() to service_role;
