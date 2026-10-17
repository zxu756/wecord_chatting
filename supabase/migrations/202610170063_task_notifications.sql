-- Notifications for tasks: assignments and due dates.
--
-- task_notifications is the inbox side: one row per person per event,
-- listed by list_task_notifications next to mentions and replies and marked
-- read by mark_task_notifications_read. Kinds:
--   assigned  somebody (actor) put the person on an item. Made by a trigger
--             on task_item_assignees, never for assigning yourself.
--   due_soon  the item is due within the hour (all-day items: within 12
--             hours of the end of their day).
--   overdue   the item's due date passed (reminded for two days after).
--
-- Push goes through the same pipeline as messages:
--
-- * Assignment, immediately. The assigner's app calls the push Edge
--   Function with {task_item_id}; the function (service role) calls
--   claim_task_assignment_push(item, caller), which hands out the pushes of
--   the assignments the caller just made, once each (pushed_at), as rows of
--   the same shape as claim_push_delivery.
--
-- * Due reminders, on a schedule. due_list_item_reminders() is meant to be
--   called by the dispatcher (the pg_cron job another part of the app runs,
--   or any cron that can use the service role) every few minutes:
--
--     select * from public.due_list_item_reminders();
--
--   It creates the due_soon and overdue notifications that are new (so every
--   person is reminded once per due date, however often it runs, and again
--   when the due date changes) and returns, for each new notification, one
--   row per push subscription to notify:
--     notification_id, user_id, subscription_id, endpoint, p256dh, auth,
--     conversation_id, circle_id, title, body
--   Deliver each row like a message push (title/body as the notification,
--   `/#/circles/<circle_id>?c=<conversation_id>&list=<list_id>` or
--   `/#/chats/<conversation_id>?list=<list_id>` as the target; see
--   supabase/functions/push/index.ts targetPath) and drop subscriptions the
--   push service reports gone with remove_push_subscriptions. People in
--   do-not-disturb or whose circle level is "none"/muted get the inbox entry
--   but no push. With pg_cron and pg_net this is one job calling an Edge
--   Function that runs the select above; the function has no other
--   requirement. The function is only executable by the service role.

create table if not exists public.task_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  item_id uuid not null references public.task_items(id) on delete cascade,
  list_id uuid not null references public.task_lists(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  title text not null,
  due_at timestamptz,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  pushed_at timestamptz,
  constraint task_notifications_kind check (kind in ('assigned', 'due_soon', 'overdue'))
);

create index if not exists task_notifications_user_idx
  on public.task_notifications (user_id, created_at desc);
-- One reminder per person, item and due date.
create unique index if not exists task_notifications_due_once_idx
  on public.task_notifications (user_id, item_id, kind, due_at)
  where kind in ('due_soon', 'overdue');

alter table public.task_notifications enable row level security;
revoke all on public.task_notifications from anon, authenticated;
-- Read through list_task_notifications only.

create or replace function public.notify_task_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  i public.task_items%rowtype;
  l public.task_lists%rowtype;
begin
  if new.assigned_by is null or new.assigned_by = new.user_id then
    return new;
  end if;
  select * into i from public.task_items where id = new.item_id;
  select * into l from public.task_lists where id = i.list_id;
  if i.id is null or l.id is null or i.deleted_at is not null then
    return new;
  end if;
  if public.are_users_blocked(new.assigned_by, new.user_id) then
    return new;
  end if;
  insert into public.task_notifications (
    user_id, kind, item_id, list_id, conversation_id, actor_id, title, due_at
  )
  values (
    new.user_id, 'assigned', i.id, l.id, l.conversation_id, new.assigned_by,
    left(i.title, 300), i.due_at
  );
  return new;
end;
$$;

revoke execute on function public.notify_task_assignment() from public, anon, authenticated;

drop trigger if exists task_item_assignees_notify on public.task_item_assignees;
create trigger task_item_assignees_notify
  after insert on public.task_item_assignees
  for each row execute function public.notify_task_assignment();

-- The caller's task notifications of the last 30 days, newest first, for
-- items they can still see.
create or replace function public.list_task_notifications(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  item_id uuid,
  list_id uuid,
  conversation_id uuid,
  actor_id uuid,
  actor_name text,
  actor_avatar_url text,
  title text,
  list_title text,
  due_at timestamptz,
  created_at timestamptz,
  is_unread boolean,
  is_done boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    n.id,
    n.kind,
    n.item_id,
    n.list_id,
    n.conversation_id,
    n.actor_id,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    i.title,
    l.title,
    i.due_at,
    n.created_at,
    n.read_at is null,
    i.completed_at is not null
  from public.task_notifications n
  join public.task_items i on i.id = n.item_id and i.deleted_at is null
  join public.task_lists l on l.id = n.list_id and l.deleted_at is null
  left join public.profiles p on p.id = n.actor_id
  where n.user_id = auth.uid()
    and n.created_at > now() - interval '30 days'
    and public.is_current_user_conversation_member(n.conversation_id)
  order by n.created_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- Marks the given notifications (all of the caller's when null) as read.
create or replace function public.mark_task_notifications_read(p_ids uuid[] default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.task_notifications
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null
    and (p_ids is null or id = any (p_ids));
end;
$$;

revoke execute on function public.list_task_notifications(integer) from public, anon;
revoke execute on function public.mark_task_notifications_read(uuid[]) from public, anon;
grant execute on function public.list_task_notifications(integer) to authenticated;
grant execute on function public.mark_task_notifications_read(uuid[]) to authenticated;

-- Push targets of the assignments [caller_id] just made on an item. Service
-- role only (the push Edge Function).
create or replace function public.claim_task_assignment_push(
  target_item_id uuid,
  caller_id uuid
)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  actor_name text;
begin
  select coalesce(nullif(btrim(p.display_name), ''), p.username, 'Someone')
  into actor_name
  from public.profiles p
  where p.id = caller_id;

  return query
  with claimed as (
    update public.task_notifications n
    set pushed_at = now()
    where n.item_id = target_item_id
      and n.kind = 'assigned'
      and n.actor_id = caller_id
      and n.pushed_at is null
      and n.created_at > now() - interval '10 minutes'
    returning n.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    c.conversation_id,
    cc.circle_id,
    coalesce(actor_name, 'Someone') || ' assigned you a task',
    c.title
  from claimed c
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(c.conversation_id)
  left join public.circle_notification_settings ns
    on ns.circle_id = cc.circle_id and ns.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and public.user_has_conversation_channel_permission(
      c.conversation_id, c.user_id, 'view_channel'
    )
    and (
      ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and ns.level <> 'none'
      )
    );
end;
$$;

-- Creates the due_soon / overdue notifications that are new and returns
-- the pushes to send (see the header). Service role only.
create or replace function public.due_list_item_reminders()
returns table (
  notification_id uuid,
  user_id uuid,
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  return query
  with candidates as (
    select
      i.id as item_id,
      i.list_id,
      l.conversation_id,
      i.title,
      i.due_at,
      case when i.due_at < now() then 'overdue' else 'due_soon' end as kind,
      coalesce(a.user_id, i.created_by) as person
    from public.task_items i
    join public.task_lists l on l.id = i.list_id and l.deleted_at is null
    left join public.task_item_assignees a on a.item_id = i.id
    where i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at > now() - interval '2 days'
      and i.due_at <= now() + case
        when i.due_has_time then interval '1 hour'
        else interval '12 hours'
      end
  ),
  inserted as (
    -- The push is claimed with the notification (pushed_at), so a second
    -- run never sends it again.
    insert into public.task_notifications (
      user_id, kind, item_id, list_id, conversation_id, title, due_at, pushed_at
    )
    select c.person, c.kind, c.item_id, c.list_id, c.conversation_id,
           left(c.title, 300), c.due_at, now()
    from candidates c
    where c.person is not null
      and exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = c.conversation_id and cm.user_id = c.person
      )
      and public.user_has_conversation_channel_permission(
        c.conversation_id, c.person, 'view_channel'
      )
    on conflict (user_id, item_id, kind, due_at)
      where kind in ('due_soon', 'overdue')
      do nothing
    returning *
  )
  select
    c.id,
    c.user_id,
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    c.conversation_id,
    cc.circle_id,
    case c.kind
      when 'overdue' then 'Task overdue'
      else 'Task due soon'
    end,
    c.title
  from inserted c
  join public.push_subscriptions s on s.user_id = c.user_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(c.conversation_id)
  left join public.circle_notification_settings ns
    on ns.circle_id = cc.circle_id and ns.user_id = c.user_id
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and (
      ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and ns.level <> 'none'
      )
    );
end;
$$;

revoke execute on function public.claim_task_assignment_push(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.due_list_item_reminders() from public, anon, authenticated;
grant execute on function public.claim_task_assignment_push(uuid, uuid) to service_role;
grant execute on function public.due_list_item_reminders() to service_role;
