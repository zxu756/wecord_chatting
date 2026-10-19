-- The one-minute dispatcher, with the second push of urgent messages (A7).
--
-- This is run_later_dispatch exactly as 202610230620_birthday_push.sql left
-- it (the latest definition: 202610170010, 202610170070, 202610190021, then
-- that one, which added `public.birthday_pushes_waiting()`; the later digest
-- migration 202610230520 and the other mentions only wake the function
-- through wake_scheduled_dispatch), with two more reasons to wake the
-- scheduled-dispatch function:
--
--   * an urgent message (message_urgent_targets, 202610240400) whose first
--     push waits, or whose second push is due 10 minutes after the first while
--     the person has not confirmed. Only one second push is ever made;
--   * a "please confirm the announcement" push (announcement_ack_reminders)
--     nobody has claimed.
--
-- Repeating scheduled messages (D4) need nothing here: sending one writes the
-- next (202610240450), and dispatch_due_scheduled_messages sends what is due.
-- A7 and D4 both ride on this single rewrite.

create or replace function public.run_later_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pushes_waiting boolean;
  functions_url text;
  dispatch_secret text;
begin
  perform public.dispatch_due_scheduled_messages();
  perform public.chat_event_due_reminders();

  -- Dismissed reminders go after a month.
  delete from public.message_reminders r
  where r.dismissed_at < now() - interval '30 days';

  select exists (
    select 1
    from public.scheduled_messages s
    where s.status = 'sent'
      and s.push_claimed_at is null
      and s.sent_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.message_reminders r
    where r.push_claimed_at is null
      and r.dismissed_at is null
      and r.remind_at <= now()
      and r.remind_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.chat_event_reminders r
    where r.push_sent_at is null
      and r.created_at > now() - interval '30 minutes'
  ) or exists (
    -- The same items due_list_item_reminders() looks at, for a member who
    -- has no notice of this kind for this due date yet.
    select 1
    from public.task_items i
    join public.task_lists l on l.id = i.list_id and l.deleted_at is null
    left join public.task_item_assignees a on a.item_id = i.id
    join public.conversation_members cm
      on cm.conversation_id = l.conversation_id
      and cm.user_id = coalesce(a.user_id, i.created_by)
    where i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at > now() - interval '2 days'
      and i.due_at <= now() + case
        when i.due_has_time then interval '1 hour'
        else interval '12 hours'
      end
      and not exists (
        select 1
        from public.task_notifications n
        where n.user_id = cm.user_id
          and n.item_id = i.id
          and n.due_at = i.due_at
          and n.kind = case when i.due_at < now() then 'overdue' else 'due_soon' end
      )
  ) or exists (
    select 1
    from public.recalled_message_media r
    where r.expired
  ) or exists (
    -- A like, comment or reply on a Moment whose push nobody has claimed
    -- (claim_moments_pushes).
    select 1
    from public.moments_notifications mn
    where mn.pushed_at is null
      and mn.created_at > now() - interval '10 minutes'
  ) or public.birthday_pushes_waiting() or exists (
    -- An urgent message (A7) whose first push nobody has claimed, or whose
    -- second push is due: 10 minutes after the first, still unconfirmed
    -- (claim_urgent_pushes).
    select 1
    from public.message_urgent_targets ut
    where ut.acked_at is null
      and (
        (
          ut.push_claimed_at is null
          and ut.created_at > now() - interval '15 minutes'
        )
        or (
          ut.repush_claimed_at is null
          and ut.push_claimed_at is not null
          and ut.push_claimed_at <= now() - interval '10 minutes'
          and ut.push_claimed_at > now() - interval '1 hour'
        )
      )
  ) or exists (
    -- A "please confirm the announcement" push nobody has claimed
    -- (claim_announcement_ack_pushes).
    select 1
    from public.announcement_ack_reminders ar
    where ar.pushed_at is null
      and ar.created_at > now() - interval '15 minutes'
  )
  into pushes_waiting;

  if not pushes_waiting then
    return;
  end if;

  begin
    select d.decrypted_secret
    into functions_url
    from vault.decrypted_secrets d
    where d.name = 'wecord_functions_url';
    select d.decrypted_secret
    into dispatch_secret
    from vault.decrypted_secrets d
    where d.name = 'wecord_dispatch_secret';

    if functions_url is null or dispatch_secret is null then
      return;
    end if;

    perform net.http_post(
      url := rtrim(functions_url, '/') || '/scheduled-dispatch',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || dispatch_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    );
  exception when others then
    -- No Vault or pg_net here: the work is done, only the push waits.
    null;
  end;
end;
$$;

revoke execute on function public.run_later_dispatch() from public, anon, authenticated;
grant execute on function public.run_later_dispatch() to service_role;
