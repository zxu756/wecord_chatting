-- L6 (scale): the push claim of a big chat comes in batches.
--
-- claim_push_delivery handed back one row per subscription of everyone who
-- should hear about a message: 6000 rows for a group of 5000 and 12000 for a
-- circle channel of 10000. The REST API cuts a function's answer at 1000
-- rows (max_rows), so everyone after the first 1000 never got the push, and
-- the one that claimed it was marked done. The Edge Function would also have
-- sent them all in one go.
--
-- Now claim_push_delivery takes an optional cursor and a batch size:
--
--   claim_push_delivery(message, caller)                   everyone, as before
--   claim_push_delivery(message, caller, null, 500)        the first 500 people
--   claim_push_delivery(message, caller, last_person, 500) the next 500
--
-- A batch is page_size people (all their subscriptions), in user id order;
-- every row carries recipient_id, the cursor for the next call. The first call
-- (no cursor) claims the message as before, so it is still pushed at most
-- once; the later calls only read on, and return nothing for a message nobody
-- claimed. A batch that comes back with fewer than page_size people is the
-- last one. Who gets a push (muted, do not disturb, blocked, no access to the
-- channel, circle notification levels), the text and its language are exactly
-- what they were: only the final query is rewritten, with the same checks.

create or replace function pg_temp.l6_patch_text(fn regprocedure, pairs text[])
returns text
language plpgsql
as $$
declare
  def text := pg_get_functiondef(fn);
  patched text;
  i integer;
begin
  for i in 1..array_length(pairs, 1) by 2 loop
    patched := replace(def, pairs[i], pairs[i + 1]);
    if patched = def then
      raise exception 'L6 patch: expected text not found in %: %', fn, left(pairs[i], 80);
    end if;
    def := patched;
  end loop;
  return def;
end $$;

do $do$
declare
  def text;
begin
  def := pg_temp.l6_patch_text('public.claim_push_delivery(uuid, uuid)'::regprocedure, array[
$old$claim_push_delivery(target_message_id uuid, caller_id uuid)$old$,
$new$claim_push_delivery(target_message_id uuid, caller_id uuid, after_user_id uuid DEFAULT NULL::uuid, page_size integer DEFAULT NULL::integer)$new$,
$old$title text, body text)$old$,
$new$title text, body text, recipient_id uuid)$new$,
-- The siblings of an album are only compared on the first call.
$old$    if exists (
      select 1
      from public.messages sibling
      join public.push_deliveries delivery on delivery.message_id = sibling.id$old$,
$new$    if after_user_id is null and exists (
      select 1
      from public.messages sibling
      join public.push_deliveries delivery on delivery.message_id = sibling.id$new$,
$old$  insert into public.push_deliveries (message_id)
  values (message.id)
  on conflict do nothing;
  if not found then
    return;
  end if;
$old$,
$new$  if after_user_id is null then
    insert into public.push_deliveries (message_id)
    values (message.id)
    on conflict do nothing;
    if not found then
      return;
    end if;
  elsif not exists (
    select 1
    from public.push_deliveries claimed
    where claimed.message_id = message.id
  ) then
    -- A later batch of a message nobody claimed.
    return;
  end if;
$new$,
$old$    case when s.language = 'zh' then body_zh else body_en end
  from public.conversation_members cm
  join public.push_subscriptions s on s.user_id = cm.user_id
  left join public.circle_notification_settings ns
    on ns.circle_id = channel.circle_id
    and ns.user_id = cm.user_id
  left join public.user_privacy_settings ups on ups.user_id = cm.user_id
  where cm.conversation_id = message.conversation_id
    and cm.user_id <> message.sender_id
    and (cm.muted_until is null or cm.muted_until < now())
    and coalesce(ups.presence_status, 'online') <> 'dnd'
    and not public.are_users_blocked(message.sender_id, cm.user_id)
    and public.user_has_conversation_channel_permission(
      message.conversation_id,
      cm.user_id,
      'view_channel'
    )
    and (
      channel.id is null
      or ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and (
          ns.level = 'all'
          or (
            ns.level = 'mentions'
            and exists (
              select 1
              from public.message_mentions mm
              where mm.message_id = message.id
                and mm.user_id = cm.user_id
            )
          )
        )
      )
    );
$old$,
$new$    case when s.language = 'zh' then body_zh else body_en end,
    recipient.user_id
  from (
    -- The people, one batch at a time, in user id order; the checks are the
    -- ones that were on the whole list before.
    select cm.user_id
    from public.conversation_members cm
    left join public.circle_notification_settings ns
      on ns.circle_id = channel.circle_id
      and ns.user_id = cm.user_id
    left join public.user_privacy_settings ups on ups.user_id = cm.user_id
    where cm.conversation_id = message.conversation_id
      and cm.user_id <> message.sender_id
      and (after_user_id is null or cm.user_id > after_user_id)
      and exists (
        select 1
        from public.push_subscriptions has_subscription
        where has_subscription.user_id = cm.user_id
      )
      and (cm.muted_until is null or cm.muted_until < now())
      and coalesce(ups.presence_status, 'online') <> 'dnd'
      and not public.are_users_blocked(message.sender_id, cm.user_id)
      and public.user_has_conversation_channel_permission(
        message.conversation_id,
        cm.user_id,
        'view_channel'
      )
      and (
        channel.id is null
        or ns.user_id is null
        or (
          (ns.muted_until is null or ns.muted_until < now())
          and (
            ns.level = 'all'
            or (
              ns.level = 'mentions'
              and exists (
                select 1
                from public.message_mentions mm
                where mm.message_id = message.id
                  and mm.user_id = cm.user_id
              )
            )
          )
        )
      )
    order by cm.user_id
    limit page_size
  ) recipient
  join public.push_subscriptions s on s.user_id = recipient.user_id
  order by recipient.user_id, s.id;
$new$
  ]);
  drop function public.claim_push_delivery(uuid, uuid);
  execute def;
end $do$;

revoke execute on function public.claim_push_delivery(uuid, uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.claim_push_delivery(uuid, uuid, uuid, integer)
  to service_role;
