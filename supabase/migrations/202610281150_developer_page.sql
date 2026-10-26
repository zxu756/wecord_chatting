-- Bot API 2.0 and the developer page (roadmap I3), part 4 of 5: what the
-- developer page (Settings -> Developer) reads.
--
-- The page is for people who can run a bot: members who manage a circle
-- (manage_circle) and so can make and change that circle's bots. Everyone else
-- does not see the entry, and these functions would give them nothing anyway.
--
-- * my_developer_access(): whether the caller manages any circle.
-- * list_my_developer_bots(): the bots of every circle the caller manages, with
--   the state of the callback address and the event subscription, whether the
--   bot is open to direct chats and groups, and how busy it was in the last day.
--   Never a token, a hash or a secret.
-- * list_bot_api_calls(bot, limit): the latest calls the bot made (method,
--   route template, status, when). Managers of the bot's circle only.

create or replace function public.my_developer_access()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  return exists (
    select 1
    from public.circle_members cm
    where cm.user_id = auth.uid()
      and public.circle_member_has_permission(cm.circle_id, auth.uid(), 'manage_circle')
  );
end;
$$;

create or replace function public.list_my_developer_bots()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(item order by circle_name, bot_name, bot_id)
    from (
      select
        c.name as circle_name,
        b.name as bot_name,
        b.id as bot_id,
        public.circle_bot_payload(b)
        || jsonb_build_object(
          'circle_name', c.name,
          'description', nullif(b.description, ''),
          'allow_direct', b.allow_direct,
          'allow_groups', b.allow_groups,
          'events', public.bot_event_subscription_state(b.id),
          'callback', public.bot_callback_state(b.id),
          'calls_last_day', (
            select count(*)
            from public.bot_api_calls k
            where k.bot_id = b.id and k.at > now() - interval '1 day'
          ),
          'last_call_at', (
            select max(k.at) from public.bot_api_calls k where k.bot_id = b.id
          )
        ) as item
      from public.circle_bots b
      join public.circles c on c.id = b.circle_id
      where public.current_user_has_circle_permission(b.circle_id, 'manage_circle')
      limit 100
    ) bots
  ), '[]'::jsonb);
end;
$$;

create or replace function public.list_bot_api_calls(
  target_bot_id uuid,
  max_count integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  return coalesce((
    select jsonb_agg(item order by at desc, id desc)
    from (
      select
        k.id,
        k.at,
        jsonb_build_object(
          'at', k.at,
          'method', k.method,
          'route', k.route,
          'status', k.status
        ) as item
      from public.bot_api_calls k
      where k.bot_id = bot.id
      order by k.at desc, k.id desc
      limit least(greatest(coalesce(max_count, 50), 1), 100)
    ) page
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.my_developer_access() from public, anon;
revoke execute on function public.list_my_developer_bots() from public, anon;
revoke execute on function public.list_bot_api_calls(uuid, integer) from public, anon;
grant execute on function public.my_developer_access() to authenticated;
grant execute on function public.list_my_developer_bots() to authenticated;
grant execute on function public.list_bot_api_calls(uuid, integer) to authenticated;
