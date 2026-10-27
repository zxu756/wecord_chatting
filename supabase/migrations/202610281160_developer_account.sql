-- Event subscriptions and the bot API 2.0 (roadmap I2, I3), part 5 of 5:
-- deleting an account, and taking your data.
--
-- * Deleting an account (profiles.deleted_at):
--     - the events that were about the person (their messages, reactions,
--       joining or leaving) are removed from the delivery queue and log
--       (bot_event_deliveries.actor_id), so nothing waits to be sent after
--       they are gone;
--     - a subscription the person set up is paused (it needs a manager), and
--       the bots they made stay with their circle.
--   Same pattern as profiles_erase_interactions (202610280660):
--   prepare_account_deletion is not rewritten.
-- * export_my_developer(user) is for the data-export Edge function (service
--   role only): the bots the person made, with their settings, the address and
--   kinds of event they subscribed, and nothing of anyone else's - never a
--   token, a hash or a secret.

create or replace function public.erase_bot_events_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_event_deliveries d where d.actor_id = new.id;

  update public.bot_event_subscriptions s
  set enabled = false, last_error = 'owner_lost_access', updated_at = now()
  where s.owner_id = new.id and s.enabled;

  return new;
end;
$$;

revoke execute on function public.erase_bot_events_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_bot_events on public.profiles;
create trigger profiles_erase_bot_events
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_bot_events_of_deleted_account();

create or replace function public.export_my_developer(target_user_id uuid)
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

  return jsonb_build_object(
    'bots', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'name', b.name,
          'circle', c.name,
          'made_at', b.created_at,
          'description', nullif(b.description, ''),
          'open_to_direct_chats', b.allow_direct,
          'open_to_groups', b.allow_groups,
          'event_address', s.url,
          'event_kinds', to_jsonb(s.events),
          'event_subscription_on', s.enabled,
          'callback_address', cb.url
        ))
        order by b.created_at desc
      )
      from public.circle_bots b
      join public.circles c on c.id = b.circle_id
      left join public.bot_event_subscriptions s on s.bot_id = b.id
      left join public.bot_callbacks cb on cb.bot_id = b.id
      where b.created_by = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_developer(uuid) from public, anon, authenticated;
grant execute on function public.export_my_developer(uuid) to service_role;
