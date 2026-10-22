-- Scheduled calls (roadmap E2), part 5 of 5: deleting an account, taking your
-- data, and tidying old links.
--
-- * Deleting an account (profiles.deleted_at) turns off every call link the
--   person made, so the links of their events stop working at once. The events
--   themselves stay, as before (the chat's, with no creator), and a repeating
--   series of theirs ends at its next turn (events2_spawn_next sees the deleted
--   account). Same pattern as profiles_erase_events2 (202610270470);
--   prepare_account_deletion is not rewritten. The call links go with the
--   account's row at the final deletion (created_by cascades).
-- * export_my_scheduled_calls(user) lists the events the person made that have
--   a call: title, start and end, whether cancelled, whether it repeats, when
--   the link works until, whether it was turned off. Never the link's code (it
--   is a way in) and nobody else's events. It is for the data-export Edge
--   Function (service role only) and reaches it inside export_my_events2
--   (202610270470), which is patched in place to add it as `calls_made`: the
--   events page and events.json of the archive list it, and no new part has
--   to be read.
-- * The links of events that ended more than a week ago are deleted once a
--   day by a job of their own (wecord-scheduled-call-links-purge, 04:41 UTC,
--   only with pg_cron installed). The event keeps the old code, which no
--   longer shows anywhere (scheduled_call_code finds no link).

create or replace function public.revoke_call_links_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.call_links cl
  set revoked_at = now()
  where cl.created_by = new.id
    and cl.revoked_at is null;
  return new;
end;
$$;

revoke execute on function public.revoke_call_links_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_revoke_call_links on public.profiles;
create trigger profiles_revoke_call_links
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.revoke_call_links_of_deleted_account();

create or replace function public.export_my_scheduled_calls(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'title', e.title,
        'starts_at', e.starts_at,
        'ends_at', e.ends_at,
        'cancelled', e.cancelled_at is not null,
        'repeats', e.recurrence,
        'link_works_until', cl.expires_at,
        'link_turned_off', cl.revoked_at is not null
      )
      order by e.starts_at desc
    )
    from public.chat_events e
    left join public.call_links cl on cl.code = e.call_link_code
    where e.created_by = target_user_id
      and e.call_link_code is not null
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.export_my_scheduled_calls(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_scheduled_calls(uuid) to service_role;

-- export_my_events2 (202610270470) gets `calls_made`, in place.
do $patch$
declare
  original text;
  patched text;
  needle text := '''events_made'', coalesce((';
begin
  original := pg_get_functiondef('public.export_my_events2(uuid)'::regprocedure);
  if original like '%export_my_scheduled_calls%' then
    return;
  end if;
  if (length(original) - length(replace(original, needle, ''))) / length(needle) <> 1 then
    raise exception 'export_my_events2 has changed: cannot add the calls';
  end if;
  patched := replace(
    original,
    needle,
    '''calls_made'', public.export_my_scheduled_calls(target_user_id),'
      || E'\n    ' || needle
  );
  execute patched;
end;
$patch$;

create or replace function public.purge_scheduled_call_links()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.call_links cl
  where cl.for_event
    and cl.expires_at is not null
    and cl.expires_at < now() - interval '7 days';
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke execute on function public.purge_scheduled_call_links()
  from public, anon, authenticated;
grant execute on function public.purge_scheduled_call_links() to service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-scheduled-call-links-purge';
    perform cron.schedule(
      'wecord-scheduled-call-links-purge',
      '41 4 * * *',
      'select public.purge_scheduled_call_links()'
    );
  end if;
exception when others then
  -- No permission to schedule (a restored or local database): it can still be
  -- run by hand.
  null;
end $$;
