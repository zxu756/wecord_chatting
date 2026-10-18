-- Circle insights count people talking, not system notices. The newcomer
-- welcome card (202610230220) is a system message sent as the new member,
-- and AutoMod alerts and call notices are system messages too: none of them
-- should make someone "active" or add to the day's message count.
--
-- Patches the current aggregate_circle_insights (202610230310) in place
-- rather than copying it, so nothing else in it changes. Days already
-- aggregated keep their numbers; from the next run on, system messages are
-- left out.
do $patch$
declare
  target oid := 'public.aggregate_circle_insights(date)'::regprocedure;
  original text := pg_get_functiondef(target);
  patched text;
begin
  if original ~ E'm\\.type <> ''system''' then
    return;
  end if;
  patched := regexp_replace(
    original,
    E'(\\n(\\s*)and m\\.webhook_id is null)',
    E'\\1\n\\2and m.type <> ''system'''
  );
  if patched = original then
    raise exception 'Could not leave system messages out of the insights';
  end if;
  execute patched;
end;
$patch$;

revoke execute on function public.aggregate_circle_insights(date)
  from public, anon, authenticated;
grant execute on function public.aggregate_circle_insights(date) to service_role;
