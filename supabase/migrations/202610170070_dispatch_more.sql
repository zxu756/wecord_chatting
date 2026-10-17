-- One dispatcher for everything the database does on its own.
--
-- run_later_dispatch (202610170010/0011) sends due scheduled messages and,
-- when pushes are waiting, wakes the scheduled-dispatch Edge Function. It
-- now also covers:
--
-- * chat event reminders (202610170050): writes the due ones every minute
--   and wakes the function while some still need their push;
-- * task due reminders (202610170063): wakes the function when an item
--   came due that nobody was reminded of yet (the function calls
--   due_list_item_reminders(), which writes the inbox entries and hands out
--   the pushes);
-- * files of expired disappearing messages (202610170020): wakes the
--   function while some wait to be removed from Storage.
--
-- So the one wecord-later-dispatch job and the DISPATCH_SECRET set up for
-- scheduled messages are all these need.

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

-- The dispatcher writes due event reminders itself now.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'chat-event-due-reminders';
  end if;
exception when others then
  null;
end;
$$;
