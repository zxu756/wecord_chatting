-- L6 scale test: the plans of the push claim's recipient query, old shape and
-- paged shape, for the big group and a circle channel. Run with:
--   sh tool/scale/run_scale.sh full after tool/scale/scale_claim_plan.sql
\set ON_ERROR_STOP on
\o /dev/null
select pg_temp.i('group') as group_id \gset
select pg_temp.i('circle') as circle_id \gset
select pg_temp.uid(1) as u1 \gset
select pg_temp.root() \gset
select pg_temp.act(:'u1') \gset
select public.send_text_message(:'group_id', 'plan msg') as gm \gset
select pg_temp.root() \gset
analyze public.conversation_members;
analyze public.push_subscriptions;
\o

\echo --- old shape, group (everyone)
explain (analyze, buffers, costs off, timing on)
select s.id
from public.conversation_members cm
join public.push_subscriptions s on s.user_id = cm.user_id
left join public.user_privacy_settings ups on ups.user_id = cm.user_id
where cm.conversation_id = :'group_id'
  and cm.user_id <> :'u1'
  and (cm.muted_until is null or cm.muted_until < now())
  and coalesce(ups.presence_status, 'online') <> 'dnd'
  and not public.are_users_blocked(:'u1', cm.user_id)
  and public.user_has_conversation_channel_permission(:'group_id', cm.user_id, 'view_channel');

\echo --- paged shape, group, 500
explain (analyze, buffers, costs off, timing on)
select s.id
from (
  select cm.user_id
  from public.conversation_members cm
  left join public.user_privacy_settings ups on ups.user_id = cm.user_id
  where cm.conversation_id = :'group_id'
    and cm.user_id <> :'u1'
    and exists (select 1 from public.push_subscriptions h where h.user_id = cm.user_id)
    and (cm.muted_until is null or cm.muted_until < now())
    and coalesce(ups.presence_status, 'online') <> 'dnd'
    and not public.are_users_blocked(:'u1', cm.user_id)
    and public.user_has_conversation_channel_permission(:'group_id', cm.user_id, 'view_channel')
  order by cm.user_id
  limit 500
) recipient
join public.push_subscriptions s on s.user_id = recipient.user_id
order by recipient.user_id, s.id;
