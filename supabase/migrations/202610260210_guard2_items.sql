-- AI guard 2.0 (roadmap F7), part 2 of 3: the titles of events, notes and
-- tasks.
--
-- Until now the guard looked at messages only, so a new member could put the
-- spam in an event title, a note title or a task. The same people the guard
-- checks (ai_guard_applies_to, 202610260200) are now checked for what they
-- write in:
--   * circle events: title and description;
--   * notes in a circle channel: the title;
--   * task lists in a circle channel: the title;
--   * tasks in them: title and details.
-- (Polls are messages and go through messages_review_scope.)
--
-- These things are not messages, so there is nothing to hide while the AI
-- looks: an item is shown at once and the check runs after it. What the AI
-- flags goes to the circle's Review queue as a card ("flagged"); a moderator
-- opens the item, deals with it with the usual tools and dismisses the card.
-- The guard's "hold" setting does not apply to them.
--
--  * guard_item_reviews: one row per item (a new edit of the same item checks
--    again, at most once a minute, and one person's items are checked ten times
--    in ten minutes at most, so editing or making things in bulk cannot be
--    used to burn the circle's AI requests).
--  * An AFTER trigger on each table records the check and wakes the `ai`
--    function through ai_guard_wake ({action: 'guard_item', review_id}), like
--    messages do. When it cannot be woken, the check ends "not checked".
--  * The function claims it (ai_guard_item_claim, which reads the live text,
--    so a deleted item is simply dropped), is charged to the circle like
--    every guard check, and answers with finish_guard_item_review.
--  * run_ai_guard_item_sweep (its own pg_cron job, every minute) ends checks
--    that never came back and tidies old rows.
--  * Moderators (manage_messages) read the queue with list_guard_item_reviews
--    and count_guard_item_reviews and close a card with
--    dismiss_guard_item_review. The AI's flags are audited as guard_item_flag
--    (no actor), dismissals as guard_item_dismiss.

create table if not exists public.guard_item_reviews (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  item_type text not null,
  item_id uuid not null,
  -- Where a note or task lives (null for a circle event).
  conversation_id uuid references public.conversations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  state text not null default 'checking',
  verdict text,
  reason text,
  reason_zh text,
  unchecked_reason text,
  created_at timestamptz not null default now(),
  check_started_at timestamptz,
  checked_at timestamptz,
  decided_at timestamptz,
  decided_by uuid references public.profiles(id) on delete set null,
  constraint guard_item_reviews_type check (
    item_type in ('circle_event', 'note', 'task_list', 'task_item')
  ),
  constraint guard_item_reviews_state check (
    state in ('checking', 'flagged', 'released', 'dismissed')
  ),
  constraint guard_item_reviews_verdict check (
    verdict is null
    or verdict in ('allow', 'spam', 'scam', 'harassment', 'sexual', 'other', 'not_checked')
  ),
  constraint guard_item_reviews_unchecked check (
    unchecked_reason is null
    or unchecked_reason in (
      'not_configured', 'ai_off', 'limit', 'error', 'timeout', 'unavailable', 'gone'
    )
  ),
  constraint guard_item_reviews_once unique (item_type, item_id)
);

create index if not exists guard_item_reviews_queue_idx
  on public.guard_item_reviews (circle_id, checked_at desc)
  where state = 'flagged';
create index if not exists guard_item_reviews_checking_idx
  on public.guard_item_reviews (created_at)
  where state = 'checking';

alter table public.guard_item_reviews enable row level security;
revoke all on public.guard_item_reviews from anon, authenticated;

-- ---------------------------------------------------------------- the text

-- The live text of an item: its title and, when it has one, the rest. Null
-- when the item is gone, deleted or cancelled.
create or replace function public.guard_item_text(p_item_type text, p_item_id uuid)
returns table (title text, detail text)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_item_type = 'circle_event' then
    return query
      select e.title, coalesce(e.description, '')
      from public.circle_events e
      where e.id = p_item_id and e.cancelled_at is null;
  elsif p_item_type = 'note' then
    return query
      select n.title, ''::text
      from public.notes n
      where n.id = p_item_id and n.deleted_at is null;
  elsif p_item_type = 'task_list' then
    return query
      select l.title, ''::text
      from public.task_lists l
      where l.id = p_item_id and l.deleted_at is null;
  elsif p_item_type = 'task_item' then
    return query
      select t.title, t.details
      from public.task_items t
      where t.id = p_item_id and t.deleted_at is null;
  end if;
end;
$$;

revoke execute on function public.guard_item_text(text, uuid) from public, anon, authenticated;
grant execute on function public.guard_item_text(text, uuid) to service_role;

-- ---------------------------------------------------------------- opening

-- Records a check of an item and wakes the function. Internal.
create or replace function public.guard_item_open(
  p_item_type text,
  p_item_id uuid,
  p_circle_id uuid,
  p_conversation_id uuid,
  p_actor_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  scope public.circle_ai_guard_scope%rowtype;
  review_id uuid;
begin
  select s.* into scope
  from public.circle_ai_guard_scope s
  where s.circle_id = p_circle_id;
  if scope.circle_id is not null and not scope.check_items then
    return;
  end if;

  if not public.ai_guard_applies_to(p_circle_id, p_actor_id) then
    return;
  end if;

  -- Not a request for each of fifty tasks made in one go: after ten checks of
  -- one person's items in ten minutes the rest wait for the next burst (what
  -- the first ten show is what a moderator needs to act on the person).
  if (
    select count(*)
    from public.guard_item_reviews r
    where r.actor_id = p_actor_id
      and r.circle_id = p_circle_id
      and r.created_at > now() - interval '10 minutes'
  ) >= 10 then
    return;
  end if;

  insert into public.guard_item_reviews as r (
    circle_id, item_type, item_id, conversation_id, actor_id
  )
  values (p_circle_id, p_item_type, p_item_id, p_conversation_id, p_actor_id)
  on conflict (item_type, item_id) do update
  set circle_id = excluded.circle_id,
    conversation_id = excluded.conversation_id,
    actor_id = excluded.actor_id,
    state = 'checking',
    verdict = null,
    reason = null,
    reason_zh = null,
    unchecked_reason = null,
    created_at = now(),
    check_started_at = null,
    checked_at = null,
    decided_at = null,
    decided_by = null
  -- A new edit counts again after a minute, not sooner.
  where r.created_at < now() - interval '60 seconds'
  returning r.id into review_id;

  if review_id is null then
    return;
  end if;

  if not public.ai_guard_wake(
    'ai',
    jsonb_build_object('action', 'guard_item', 'review_id', review_id)
  ) then
    perform public.finish_guard_item_review(review_id, 'not_checked', null, null, 'unavailable');
  end if;
end;
$$;

revoke execute on function public.guard_item_open(text, uuid, uuid, uuid, uuid) from public, anon, authenticated;

-- One trigger function for the four tables.
create or replace function public.guard_items_after_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  row_data jsonb := to_jsonb(new);
  actor uuid := auth.uid();
  item_type text;
  conv uuid;
  channel_circle uuid;
begin
  if actor is null then
    return null;
  end if;

  if tg_table_name = 'circle_events' then
    item_type := 'circle_event';
    channel_circle := (row_data ->> 'circle_id')::uuid;
  else
    if tg_table_name = 'notes' then
      item_type := 'note';
      conv := (row_data ->> 'conversation_id')::uuid;
    elsif tg_table_name = 'task_lists' then
      item_type := 'task_list';
      conv := (row_data ->> 'conversation_id')::uuid;
    else
      item_type := 'task_item';
      select l.conversation_id into conv
      from public.task_lists l
      where l.id = (row_data ->> 'list_id')::uuid;
    end if;
    if conv is null then
      return null;
    end if;
    select cc.circle_id into channel_circle
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(conv);
  end if;

  if channel_circle is null then
    return null;
  end if;

  perform public.guard_item_open(
    item_type, (row_data ->> 'id')::uuid, channel_circle, conv, actor
  );
  return null;
end;
$$;

revoke execute on function public.guard_items_after_write() from public, anon, authenticated;


-- Insert and a changed text are separate triggers: a WHEN clause cannot tell
-- the two apart.
drop trigger if exists guard_items_circle_events_ins on public.circle_events;
create trigger guard_items_circle_events_ins
  after insert on public.circle_events
  for each row execute function public.guard_items_after_write();
drop trigger if exists guard_items_circle_events_upd on public.circle_events;
create trigger guard_items_circle_events_upd
  after update of title, description on public.circle_events
  for each row
  when (
    old.title is distinct from new.title
    or old.description is distinct from new.description
  )
  execute function public.guard_items_after_write();

drop trigger if exists guard_items_notes_ins on public.notes;
create trigger guard_items_notes_ins
  after insert on public.notes
  for each row execute function public.guard_items_after_write();
drop trigger if exists guard_items_notes_upd on public.notes;
create trigger guard_items_notes_upd
  after update of title on public.notes
  for each row
  when (old.title is distinct from new.title)
  execute function public.guard_items_after_write();

drop trigger if exists guard_items_task_lists_ins on public.task_lists;
create trigger guard_items_task_lists_ins
  after insert on public.task_lists
  for each row execute function public.guard_items_after_write();
drop trigger if exists guard_items_task_lists_upd on public.task_lists;
create trigger guard_items_task_lists_upd
  after update of title on public.task_lists
  for each row
  when (old.title is distinct from new.title)
  execute function public.guard_items_after_write();

drop trigger if exists guard_items_task_items_ins on public.task_items;
create trigger guard_items_task_items_ins
  after insert on public.task_items
  for each row execute function public.guard_items_after_write();
drop trigger if exists guard_items_task_items_upd on public.task_items;
create trigger guard_items_task_items_upd
  after update of title, details on public.task_items
  for each row
  when (
    old.title is distinct from new.title
    or old.details is distinct from new.details
  )
  execute function public.guard_items_after_write();

-- ---------------------------------------------------------- the AI's side

-- Claims a check for the `ai` function: the circle, the live text and whether
-- the circle still allows AI. Nothing when it is not waiting any more or
-- another call has it (45 seconds). An item that is gone ends the check.
create or replace function public.ai_guard_item_claim(p_review_id uuid)
returns table (circle_id uuid, item_type text, title text, detail text, ai_enabled boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed public.guard_item_reviews%rowtype;
  live record;
begin
  update public.guard_item_reviews r
  set check_started_at = now()
  where r.id = p_review_id
    and r.state = 'checking'
    and (r.check_started_at is null or r.check_started_at < now() - interval '45 seconds')
  returning r.* into claimed;
  if claimed.id is null then
    return;
  end if;

  select t.title, t.detail into live
  from public.guard_item_text(claimed.item_type, claimed.item_id) t;
  if live.title is null or (btrim(live.title) = '' and btrim(coalesce(live.detail, '')) = '') then
    perform public.finish_guard_item_review(claimed.id, 'not_checked', null, null, 'gone');
    return;
  end if;

  return query
    select claimed.circle_id, claimed.item_type, live.title, live.detail, ci.ai_enabled
    from public.circles ci
    where ci.id = claimed.circle_id;
end;
$$;

-- The AI's answer (or its absence). Returns the new state or null.
create or replace function public.finish_guard_item_review(
  p_review_id uuid,
  p_verdict text,
  p_reason text default null,
  p_reason_zh text default null,
  p_unchecked_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  review public.guard_item_reviews%rowtype;
  flagged boolean;
  new_state text;
  clean_reason text := nullif(left(btrim(coalesce(p_reason, '')), 240), '');
  clean_reason_zh text := nullif(left(btrim(coalesce(p_reason_zh, '')), 240), '');
  item_title text;
  channel public.circle_channels%rowtype;
begin
  if p_verdict is null
    or p_verdict not in ('allow', 'spam', 'scam', 'harassment', 'sexual', 'other', 'not_checked')
  then
    raise exception 'Unknown verdict' using errcode = '22023';
  end if;

  select r.* into review
  from public.guard_item_reviews r
  where r.id = p_review_id and r.state = 'checking'
  for update;
  if review.id is null then
    return null;
  end if;

  flagged := p_verdict not in ('allow', 'not_checked');
  new_state := case when flagged then 'flagged' else 'released' end;

  update public.guard_item_reviews r
  set state = new_state,
    verdict = p_verdict,
    reason = case when flagged then clean_reason end,
    reason_zh = case when flagged then clean_reason_zh end,
    unchecked_reason = case
      when p_verdict = 'not_checked' then coalesce(p_unchecked_reason, 'error')
    end,
    checked_at = now()
  where r.id = p_review_id;

  if flagged then
    select t.title into item_title
    from public.guard_item_text(review.item_type, review.item_id) t;
    select cc.* into channel
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(review.conversation_id);

    insert into public.circle_audit_log (
      circle_id, actor_id, action, target_type, target_id, target_label, changes
    )
    values (
      review.circle_id,
      null,
      'guard_item_flag',
      'item',
      review.item_id,
      public.circle_member_label(review.circle_id, review.actor_id),
      jsonb_strip_nulls(jsonb_build_object(
        'item_type', review.item_type,
        'title', left(item_title, 120),
        'verdict', p_verdict,
        'reason', clean_reason,
        'author_id', review.actor_id,
        'channel_id', channel.id,
        'channel_name', channel.name
      ))
    );
  end if;

  return new_state;
end;
$$;

revoke execute on function public.ai_guard_item_claim(uuid) from public, anon, authenticated;
revoke execute on function public.finish_guard_item_review(uuid, text, text, text, text) from public, anon, authenticated;
grant execute on function public.ai_guard_item_claim(uuid) to service_role;
grant execute on function public.finish_guard_item_review(uuid, text, text, text, text) to service_role;

-- Ends checks that never came back and drops old rows. Its own cron job.
create or replace function public.run_ai_guard_item_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  stale uuid;
begin
  for stale in
    select r.id
    from public.guard_item_reviews r
    where r.state = 'checking'
      and r.created_at < now() - interval '60 seconds'
    order by r.created_at
    limit 200
  loop
    perform public.finish_guard_item_review(stale, 'not_checked', null, null, 'timeout');
  end loop;

  delete from public.guard_item_reviews r
  where (r.state = 'released' and r.checked_at < now() - interval '3 days')
    or (r.state = 'dismissed' and r.decided_at < now() - interval '30 days');
end;
$$;

revoke execute on function public.run_ai_guard_item_sweep() from public, anon, authenticated;
grant execute on function public.run_ai_guard_item_sweep() to service_role;

-- ------------------------------------------------------------ the queue

create or replace function public.list_guard_item_reviews(
  target_circle_id uuid,
  max_results integer default 50
)
returns table (
  id uuid,
  item_type text,
  item_id uuid,
  conversation_id uuid,
  channel_id uuid,
  channel_name text,
  actor_id uuid,
  actor_name text,
  actor_avatar_url text,
  title text,
  detail text,
  verdict text,
  reason text,
  reason_zh text,
  flagged_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_messages') then
    raise exception 'Only moderators can see this' using errcode = '42501';
  end if;

  return query
  select
    r.id,
    r.item_type,
    r.item_id,
    r.conversation_id,
    cc.id,
    cc.name,
    r.actor_id,
    public.circle_member_label(r.circle_id, r.actor_id),
    coalesce(cm.avatar_url, p.avatar_url),
    live.title,
    left(coalesce(live.detail, ''), 300),
    r.verdict,
    r.reason,
    r.reason_zh,
    r.checked_at
  from public.guard_item_reviews r
  cross join lateral public.guard_item_text(r.item_type, r.item_id) live
  join public.profiles p on p.id = r.actor_id
  left join public.circle_members cm
    on cm.circle_id = r.circle_id and cm.user_id = r.actor_id
  left join public.circle_channels cc
    on cc.id = public.conversation_circle_channel_id(r.conversation_id)
  where r.circle_id = target_circle_id
    and r.state = 'flagged'
  order by r.checked_at desc, r.id desc
  limit least(greatest(coalesce(max_results, 50), 1), 100);
end;
$$;

create or replace function public.count_guard_item_reviews(target_circle_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
    or not public.current_user_has_circle_permission(target_circle_id, 'manage_messages')
  then
    return 0;
  end if;
  return (
    select count(*)::integer
    from (
      select 1
      from public.guard_item_reviews r
      cross join lateral public.guard_item_text(r.item_type, r.item_id) live
      where r.circle_id = target_circle_id and r.state = 'flagged'
      limit 99
    ) waiting
  );
end;
$$;

-- Closes a flagged card (the moderator has dealt with the item, or finds it
-- fine).
create or replace function public.dismiss_guard_item_review(target_review_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  review public.guard_item_reviews%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select r.* into review
  from public.guard_item_reviews r
  where r.id = target_review_id and r.state = 'flagged'
  for update;
  if review.id is null then
    raise exception 'This was already reviewed' using errcode = 'P0002';
  end if;
  if not public.current_user_has_circle_permission(review.circle_id, 'manage_messages') then
    raise exception 'Only moderators can review this' using errcode = '42501';
  end if;

  update public.guard_item_reviews r
  set state = 'dismissed', decided_at = now(), decided_by = auth.uid()
  where r.id = target_review_id;

  perform public.write_circle_audit(
    review.circle_id,
    'guard_item_dismiss',
    'item',
    review.item_id,
    public.circle_member_label(review.circle_id, review.actor_id),
    jsonb_strip_nulls(jsonb_build_object(
      'item_type', review.item_type,
      'verdict', review.verdict,
      'author_id', review.actor_id
    ))
  );
  return 'dismissed';
end;
$$;

revoke execute on function public.list_guard_item_reviews(uuid, integer) from public, anon;
revoke execute on function public.count_guard_item_reviews(uuid) from public, anon;
revoke execute on function public.dismiss_guard_item_review(uuid) from public, anon;
grant execute on function public.list_guard_item_reviews(uuid, integer) to authenticated;
grant execute on function public.count_guard_item_reviews(uuid) to authenticated;
grant execute on function public.dismiss_guard_item_review(uuid) to authenticated;

-- ------------------------------------------------------------ schedule

-- Its own cron job, beside wecord-ai-guard-sweep; run_later_dispatch() is
-- not touched.
create or replace function public.install_ai_guard_item_schedule()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return 'pg_cron is not enabled';
  end if;
  perform cron.schedule(
    'wecord-ai-guard-item-sweep',
    '* * * * *',
    'select public.run_ai_guard_item_sweep()'
  );
  return 'scheduled';
end;
$$;

revoke execute on function public.install_ai_guard_item_schedule() from public, anon, authenticated;
grant execute on function public.install_ai_guard_item_schedule() to service_role;

do $$
begin
  raise notice 'AI guard item sweep: %', public.install_ai_guard_item_schedule();
exception when others then
  raise notice 'Could not schedule the AI guard item sweep: %', sqlerrm;
end;
$$;
