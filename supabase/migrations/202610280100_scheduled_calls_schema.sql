-- Scheduled calls (roadmap E2), part 1 of 5: an event of a chat can carry a
-- call.
--
-- "Thursday 8 pm, voice meeting": the organiser switches "attach a call" on
-- when making the event (chat events: events in group chats and direct
-- messages, 202610170050 and Events 2.0, 202610270410). The event then holds a
-- call link (call_links, 202610170040) to its own chat, and everything that
-- already belongs to events carries it along:
--
--   * the reminders (202610280120) say that there is a call and, from 20
--     minutes before the start, open the call link when tapped;
--   * the card, the details and the pinned strip show "In progress · Join"
--     from 15 minutes before the start until the end (the app decides this
--     from the event's times; the link itself works until an hour after the
--     end, so a call that runs over can still be joined again);
--   * My agenda (D2) and the calendar subscription carry the call link of an
--     event (202610280130);
--   * a repeating event (C10) makes the next occurrence's call by itself;
--   * moving the event moves its link's expiry, cancelling it turns the link
--     off.
--
-- The link grants nothing by itself, as before: opening it joins the chat's
-- call only for people who could call there anyway (resolve_call_link). Calls
-- are in group and direct chats; circle events with a voice channel already
-- have their own "Join" for that channel.
--
-- This migration is the schema and the small helpers:
--
--   call_links.for_event   marks the links events made. They are not the
--                          person's own links: create_call_link does not count
--                          them towards the 50 a person may hold and
--                          list_call_links does not list them (both patched in
--                          place on their only definition, 202610170040).
--   chat_events.call_link_code   the link's code, or null.
--   scheduled_call_ends_at / scheduled_call_expiry   when the call is over, and
--                          when its link stops working (an hour later).
--   scheduled_call_code    a code, if the link behind it still works.
--   scheduled_call_make_link   makes the link of an event.

alter table public.call_links
  add column if not exists for_event boolean not null default false;

alter table public.chat_events
  add column if not exists call_link_code text;

alter table public.chat_events
  drop constraint if exists chat_events_call_link_code_check;
alter table public.chat_events
  add constraint chat_events_call_link_code_check
  check (call_link_code is null or char_length(call_link_code) = 12);

create index if not exists chat_events_call_link_idx
  on public.chat_events (call_link_code)
  where call_link_code is not null;

-- Cleaning up old event links by date.
create index if not exists call_links_event_expiry_idx
  on public.call_links (expires_at)
  where for_event;

-- The end of an event: its end, or two hours after the start (as for the
-- cards and reminders everywhere else).
create or replace function public.scheduled_call_ends_at(
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select coalesce(p_ends_at, p_starts_at + interval '2 hours');
$$;

-- When the link of an event stops working: an hour after the event is over,
-- so a call that ran long can still be joined again.
create or replace function public.scheduled_call_expiry(
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = public
as $$
  select public.scheduled_call_ends_at(p_starts_at, p_ends_at) + interval '1 hour';
$$;

-- [p_code] when the link behind it exists, is not turned off and has not
-- expired; otherwise null. What the payloads and pushes put out.
create or replace function public.scheduled_call_code(p_code text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select cl.code
  from public.call_links cl
  where p_code is not null
    and cl.code = p_code
    and cl.revoked_at is null
    and (cl.expires_at is null or cl.expires_at > now());
$$;

-- Makes the call link of an event of [p_conversation_id], in the name of
-- [p_user_id], working until [p_expires_at]. Returns its code.
create or replace function public.scheduled_call_make_link(
  p_conversation_id uuid,
  p_user_id uuid,
  p_expires_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  attempts integer := 0;
begin
  loop
    begin
      insert into public.call_links (
        code, created_by, conversation_id, expires_at, for_event
      )
      values (
        public.generate_call_link_code(),
        p_user_id,
        p_conversation_id,
        p_expires_at,
        true
      )
      returning code into new_code;
      return new_code;
    exception when unique_violation then
      attempts := attempts + 1;
      if attempts >= 5 then
        raise;
      end if;
    end;
  end loop;
end;
$$;

revoke execute on function public.scheduled_call_ends_at(timestamptz, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.scheduled_call_expiry(timestamptz, timestamptz)
  from public, anon, authenticated;
revoke execute on function public.scheduled_call_code(text)
  from public, anon, authenticated;
revoke execute on function public.scheduled_call_make_link(uuid, uuid, timestamptz)
  from public, anon, authenticated;

-- The links events made are not the person's own: they do not use up the 50
-- active links a person may hold, and the "call links" sheet does not list
-- them. Both functions are patched in place (their only definition is
-- 202610170040_call_links.sql), so nothing else in them changes.
do $patch$
declare
  original text;
  patched text;
begin
  original := pg_get_functiondef('public.create_call_link(uuid, uuid, text)'::regprocedure);
  if original not like '%for_event%' then
    patched := replace(
      original,
      'where cl.created_by = current_user_id',
      E'where cl.created_by = current_user_id\n      and not cl.for_event'
    );
    if patched = original then
      raise exception 'Could not patch create_call_link';
    end if;
    execute patched;
  end if;

  original := pg_get_functiondef('public.list_call_links(uuid, uuid)'::regprocedure);
  if original not like '%for_event%' then
    patched := replace(
      original,
      'and cl.created_by = auth.uid()',
      E'and cl.created_by = auth.uid()\n    and not cl.for_event'
    );
    if patched = original then
      raise exception 'Could not patch list_call_links';
    end if;
    execute patched;
  end if;
end;
$patch$;
