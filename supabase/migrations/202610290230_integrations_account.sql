-- Rich webhooks, RSS feeds and GitHub (roadmap I6), part 4 of 4: leaving
-- WeCord and taking your data.
--
-- * Deleting an account (profiles.deleted_at):
--     - the feeds and GitHub connections the person made stay with their
--       circle but pause themselves (creator_gone) and lose the person they
--       posted as (the hidden webhook row's created_by): they cannot post as
--       nobody. Someone with "manage webhooks" who turns one back on becomes
--       the person it posts as (set_channel_feed_enabled,
--       set_github_hook_enabled). A feed also forgets its lease, so nothing
--       is read for an account that is gone;
--     - messages a feed or connection posted AS them are theirs like any
--       message and go with the rest of their messages.
--   Same pattern as profiles_erase_workflows (202610281340);
--   prepare_account_deletion is not rewritten.
-- * export_my_integrations(user) is for the data-export Edge Function (service
--   role only): the feeds and GitHub connections the person made, in circles
--   they are still in - where, the address of the feed, the name, the events,
--   whether it is on - and never a secret.

create or replace function public.erase_integrations_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.channel_feeds f
  set enabled = false, paused_reason = 'creator_gone', lease_until = null
  from public.circle_webhooks w
  where w.id = f.webhook_id and w.created_by = new.id;

  update public.channel_github_hooks h
  set enabled = false, paused_reason = 'creator_gone'
  from public.circle_webhooks w
  where w.id = h.webhook_id and w.created_by = new.id;

  update public.circle_webhooks w
  set created_by = null
  where w.created_by = new.id and w.kind in ('rss', 'github');
  return new;
end;
$$;

revoke execute on function public.erase_integrations_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_integrations on public.profiles;
create trigger profiles_erase_integrations
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_integrations_of_deleted_account();

create or replace function public.export_my_integrations(target_user_id uuid)
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
    'feeds', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'circle', c.name,
          'channel', cc.name,
          'address', f.url,
          'title', f.title,
          'running', f.enabled,
          'paused_reason', f.paused_reason,
          'added_at', f.created_at
        ))
        order by f.created_at desc, f.id
      )
      from public.channel_feeds f
      join public.circle_webhooks w on w.id = f.webhook_id
      join public.circles c on c.id = f.circle_id
      join public.circle_channels cc on cc.id = f.channel_id
      where w.created_by = target_user_id
        and exists (
          select 1 from public.circle_members cm
          where cm.circle_id = f.circle_id and cm.user_id = target_user_id
        )
    ), '[]'::jsonb),
    'github', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'circle', c.name,
          'channel', cc.name,
          'name', h.label,
          'events', to_jsonb(h.events),
          'running', h.enabled,
          'paused_reason', h.paused_reason,
          'added_at', h.created_at
        ))
        order by h.created_at desc, h.id
      )
      from public.channel_github_hooks h
      join public.circle_webhooks w on w.id = h.webhook_id
      join public.circles c on c.id = h.circle_id
      join public.circle_channels cc on cc.id = h.channel_id
      where w.created_by = target_user_id
        and exists (
          select 1 from public.circle_members cm
          where cm.circle_id = h.circle_id and cm.user_id = target_user_id
        )
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_integrations(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_integrations(uuid) to service_role;
