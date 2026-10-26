-- Scheduled calls (roadmap E2), part 4 of 5: My agenda (D2) and the calendar
-- subscription know about the call of an event.
--
-- agenda_items_core (202610210510_my_agenda.sql, its only definition) is
-- patched in place: the `meta` of a chat event row also carries
-- call_link_code, the code of the event's call link while it works (null for
-- an event without a call, or once the link stopped). get_my_agenda and
-- agenda_items_for_user (the door of the calendar-feed function) pass meta
-- through as they always did, so the app's agenda and the calendar feed both
-- get it. The feed writes the link into the calendar entry only for a person
-- who switched on "include titles and details" (see calendar-feed/feed.ts).
--
-- Everything else in the function, which hides things the person may no longer
-- see, stays as it is.

do $patch$
declare
  original text;
  patched text;
  needle text := 'jsonb_build_object(''status'', r.status)';
begin
  original := pg_get_functiondef(
    'public.agenda_items_core(timestamptz, timestamptz, text[])'::regprocedure
  );
  if original like '%scheduled_call_code%' then
    return;
  end if;
  if (length(original) - length(replace(original, needle, ''))) / length(needle) <> 1 then
    raise exception 'agenda_items_core has changed: cannot add the call';
  end if;
  patched := replace(
    original,
    needle,
    'jsonb_build_object(''status'', r.status, ''call_link_code'', public.scheduled_call_code(e.call_link_code))'
  );
  execute patched;
end;
$patch$;
