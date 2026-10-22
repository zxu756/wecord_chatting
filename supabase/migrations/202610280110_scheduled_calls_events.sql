-- Scheduled calls (roadmap E2), part 2 of 5: switching the call of an event on
-- and off, and keeping it right as the event changes.
--
-- Nothing is rewritten; four functions are patched in place on their newest
-- definition (202610270410_events2_chat_events.sql), each with a check that
-- the patch took:
--
--   chat_event_json    plus call_link_code: the code of the event's call link
--                      while it works (scheduled_call_code), else null
--   create_chat_event  after the event is made, event_options.call = true
--                      attaches a call (scheduled_call_apply)
--   update_chat_event  the same, to switch it on or off; an update that sends
--                      no `call` key (an older app) leaves the call as it is
--
-- scheduled_call_apply makes the call link of an event, or turns it off. The
-- person has to be allowed to call in the chat (can_current_user_call_in_conversation:
-- a member, not blocked, and in a direct chat the other person takes calls
-- from them). Triggers keep the link right without any caller doing anything:
--
--   chat_events_call_sync     moving an event (start or end) moves its link's
--                             expiry; cancelling the event turns the link off
--   chat_events_call_inherit  the next occurrence of a repeating event
--                             (events2_spawn_next, 202610270430, is not
--                             touched) gets a call of its own when the one
--                             before had a call. Switching the call off on an
--                             occurrence stops the next ones from having it.

create or replace function public.scheduled_call_apply(
  p_event public.chat_events,
  p_options jsonb
)
returns public.chat_events
language plpgsql
security definer
set search_path = public
as $$
declare
  want boolean;
  working_code text := public.scheduled_call_code(p_event.call_link_code);
  result public.chat_events%rowtype;
begin
  result := p_event;

  if p_options is not null
    and jsonb_typeof(p_options) = 'object'
    and p_options ? 'call'
  then
    want := (p_options -> 'call') = 'true'::jsonb;
  else
    -- Not asked: it stays as it is.
    return result;
  end if;

  if want and working_code is null then
    if p_event.cancelled_at is not null then
      raise exception 'This event was cancelled' using errcode = '22023';
    end if;
    if not public.can_current_user_call_in_conversation(p_event.conversation_id) then
      raise exception 'You cannot call in this conversation' using errcode = '42501';
    end if;
    update public.chat_events e
    set call_link_code = public.scheduled_call_make_link(
      p_event.conversation_id,
      auth.uid(),
      public.scheduled_call_expiry(p_event.starts_at, p_event.ends_at)
    )
    where e.id = p_event.id
    returning e.* into result;
  elsif not want and p_event.call_link_code is not null then
    update public.call_links cl
    set revoked_at = coalesce(cl.revoked_at, now())
    where cl.code = p_event.call_link_code;
    update public.chat_events e
    set call_link_code = null
    where e.id = p_event.id
    returning e.* into result;
  end if;

  return result;
end;
$$;

revoke execute on function public.scheduled_call_apply(public.chat_events, jsonb)
  from public, anon, authenticated;

-- ------------------------------------------------------------- the patches

do $patch$
declare
  original text;
  patched text;
  needle text;
begin
  -- chat_event_json: the code of the call link.
  original := pg_get_functiondef('public.chat_event_json(public.chat_events)'::regprocedure);
  if original not like '%scheduled_call_code%' then
    needle := '''photo_count'', (';
    if (length(original) - length(replace(original, needle, ''))) / length(needle) <> 1 then
      raise exception 'chat_event_json has changed: cannot add the call';
    end if;
    patched := replace(
      original,
      needle,
      '''call_link_code'', public.scheduled_call_code(event_row.call_link_code),'
        || E'\n    ' || needle
    );
    execute patched;
  end if;

  -- create_chat_event: attach the call asked for in event_options.
  original := pg_get_functiondef(
    'public.create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean, jsonb)'::regprocedure
  );
  if original not like '%scheduled_call_apply%' then
    needle := '  return public.chat_event_json(new_event);';
    if (length(original) - length(replace(original, needle, ''))) / length(needle) <> 1 then
      raise exception 'create_chat_event has changed: cannot add the call';
    end if;
    patched := replace(
      original,
      needle,
      E'  new_event := public.scheduled_call_apply(new_event, event_options);\n' || needle
    );
    execute patched;
  end if;

  -- update_chat_event: switch it on or off.
  original := pg_get_functiondef(
    'public.update_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], jsonb)'::regprocedure
  );
  if original not like '%scheduled_call_apply%' then
    needle := '  return public.chat_event_json(current_event);';
    if (length(original) - length(replace(original, needle, ''))) / length(needle) <> 1 then
      raise exception 'update_chat_event has changed: cannot add the call';
    end if;
    patched := replace(
      original,
      needle,
      E'  current_event := public.scheduled_call_apply(current_event, event_options);\n' || needle
    );
    execute patched;
  end if;
end;
$patch$;

-- --------------------------------------------------------------- triggers

-- A moved event moves its link's expiry; a cancelled event turns it off.
create or replace function public.chat_events_call_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.call_link_code is not null then
    update public.call_links cl
    set expires_at = public.scheduled_call_expiry(new.starts_at, new.ends_at),
        revoked_at = case
          when new.cancelled_at is not null then coalesce(cl.revoked_at, now())
          else cl.revoked_at
        end
    where cl.code = new.call_link_code
      and cl.for_event;
  end if;
  return new;
end;
$$;

revoke execute on function public.chat_events_call_sync()
  from public, anon, authenticated;

drop trigger if exists chat_events_call_sync on public.chat_events;
create trigger chat_events_call_sync
  after update of starts_at, ends_at, cancelled_at on public.chat_events
  for each row
  when (
    new.call_link_code is not null
    and (
      old.starts_at is distinct from new.starts_at
      or old.ends_at is distinct from new.ends_at
      or old.cancelled_at is distinct from new.cancelled_at
    )
  )
  execute function public.chat_events_call_sync();

-- The next occurrence of a repeating event has a call when the one before did.
create or replace function public.chat_events_call_inherit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  before_has_call boolean;
begin
  if new.call_link_code is not null
    or new.series_id is null
    or new.created_by is null
  then
    return new;
  end if;

  select x.call_link_code is not null
  into before_has_call
  from public.chat_events x
  where x.series_id = new.series_id
    and x.id <> new.id
    and x.starts_at < new.starts_at
  order by x.starts_at desc
  limit 1;

  if coalesce(before_has_call, false) then
    new.call_link_code := public.scheduled_call_make_link(
      new.conversation_id,
      new.created_by,
      public.scheduled_call_expiry(new.starts_at, new.ends_at)
    );
  end if;
  return new;
end;
$$;

revoke execute on function public.chat_events_call_inherit()
  from public, anon, authenticated;

drop trigger if exists chat_events_call_inherit on public.chat_events;
create trigger chat_events_call_inherit
  before insert on public.chat_events
  for each row
  when (new.series_id is not null and new.call_link_code is null)
  execute function public.chat_events_call_inherit();
