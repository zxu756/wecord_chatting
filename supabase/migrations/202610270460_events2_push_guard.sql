-- Events 2.0 (roadmap C10), part 7a of 7: the push for a seat that opened up,
-- and the AI guard reading an event's questions.
--
-- * claim_event_notice_pushes(): "you moved up from the waiting list". One row
--   per device, worded in the device's language ('en' or 'zh'), with the start
--   as a <t:unix:f> token the dispatcher writes in the device's own zone.
--   scheduled-dispatch claims it (events2_promote wakes that function). It is
--   closed without a push when it is over 15 minutes old by the time the
--   function gets to it, and it sends nothing for:
--     - an event that was cancelled or is over;
--     - somebody who left the chat or the circle since;
--     - a chat the person muted, or a circle they set to no notifications or
--       muted;
--     - a circle an admin suspended (K1).
--   A chat event's push carries its conversation (so the dispatcher says only
--   "something came" when the person locked that chat, G2, and holds it back
--   in quiet hours, A4); a circle event in a channel carries the channel's
--   conversation for the same reason. Names are cleaned of angle brackets, so a
--   title cannot pass for a time token.
-- * The AI guard (F7) checks a circle event's title and description when it is
--   made or edited (202610260210). The questions are text other members read, so
--   guard_item_text now hands the guard their labels with the description, and
--   a changed set of questions starts a check like a changed description. Done
--   in place on the current guard_item_text; guard_items_after_write (which D6
--   patched) is not touched.

create or replace function public.claim_event_notice_pushes()
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
  update public.event_notices n
  set push_claimed_at = now()
  where n.push_claimed_at is null
    and n.created_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.event_notices n
    set push_claimed_at = now()
    where n.push_claimed_at is null
    returning n.*
  ),
  named as (
    select
      c.id as notice_id,
      c.user_id,
      e.conversation_id as notice_conversation_id,
      null::uuid as notice_circle_id,
      e.id as event_id,
      btrim(replace(replace(e.title, '<', ''), '>', '')) as event_title,
      e.starts_at,
      '/#/chats/' || e.conversation_id::text as notice_url
    from claimed c
    join public.chat_events e on e.id = c.chat_event_id
    join public.conversation_members cm
      on cm.conversation_id = e.conversation_id and cm.user_id = c.user_id
    where e.cancelled_at is null
      and coalesce(e.ends_at, e.starts_at + interval '2 hours') > now()
      and (cm.muted_until is null or cm.muted_until < now())

    union all

    select
      c.id,
      c.user_id,
      ch.conversation_id,
      e.circle_id,
      e.id,
      btrim(replace(replace(e.title, '<', ''), '>', '')),
      e.starts_at,
      '/#/circles/' || e.circle_id::text || '/events?event=' || e.id::text
    from claimed c
    join public.circle_events e on e.id = c.circle_event_id
    join public.circles ci on ci.id = e.circle_id and ci.disabled_mode is distinct from 'suspend'
    join public.circle_members cm
      on cm.circle_id = e.circle_id and cm.user_id = c.user_id
    left join public.circle_channels ch on ch.id = e.channel_id
    left join public.circle_notification_settings ns
      on ns.circle_id = e.circle_id and ns.user_id = c.user_id
    where e.cancelled_at is null
      and public.circle_event_ends_at(e.starts_at, e.ends_at) > now()
      and coalesce(ns.level, 'all') <> 'none'
      and (ns.muted_until is null or ns.muted_until < now())
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    d.notice_conversation_id,
    null::uuid,
    case
      when s.language = 'zh' then '你已报名成功'
      else 'You got a seat'
    end,
    case
      when s.language = 'zh' then
        '有人退出了，你已从候补转为报名成功：「' || d.event_title || '」，'
          || '<t:' || floor(extract(epoch from d.starts_at))::bigint || ':f> 开始。'
      else
        'Someone dropped out and you moved up from the waiting list: "'
          || d.event_title || '", starts <t:'
          || floor(extract(epoch from d.starts_at))::bigint || ':f>.'
    end,
    'event-seat-' || d.notice_id::text,
    d.notice_url
  from named d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_event_notice_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_event_notice_pushes() to service_role;

-- The guard reads an event's questions with its description.
do $patch$
declare
  target record;
  original text;
  patched text;
  found_any boolean := false;
begin
  for target in
    select p.oid
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'guard_item_text'
  loop
    found_any := true;
    original := pg_get_functiondef(target.oid);
    if original like '%events2_question_labels%' then
      continue;
    end if;
    patched := regexp_replace(
      original,
      'coalesce\(e\.description, (''''(::text)?)\)',
      'btrim(coalesce(e.description, ''''::text) || chr(10) || public.events2_question_labels(e.questions))'
    );
    if patched = original then
      raise exception 'Could not add the questions to guard_item_text';
    end if;
    execute patched;
  end loop;
  if not found_any then
    raise exception 'guard_item_text does not exist';
  end if;
end;
$patch$;

drop trigger if exists guard_items_circle_events_questions on public.circle_events;
create trigger guard_items_circle_events_questions
  after update of questions on public.circle_events
  for each row
  when (old.questions is distinct from new.questions)
  execute function public.guard_items_after_write();
