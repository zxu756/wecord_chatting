-- Interactive components and interaction callbacks (roadmap I1), part 6 of 6:
-- deleting an account, and taking your data.
--
-- * Deleting an account (profiles.deleted_at) erases what the person pressed or
--   typed into bots' components and commands (bot_interactions: what they
--   chose, what they typed in a form) and the bots' private replies to them.
--   Same pattern as profiles_erase_events2 (202610270470): prepare_account_deletion
--   is not rewritten. Messages bots wrote stay, as other people's messages do.
-- * export_my_interactions(user) is for the data-export Edge function (service
--   role only, like export_my_events2). What the person did, and only that:
--     - presses: their slash commands and presses on components in the last 7
--       days (older rows are removed by purge_bot_interactions), with the bot,
--       the circle, what they chose or typed and whether the bot answered;
--     - private_replies: what bots said to them privately that has not expired.
--   Nothing from other people, and never a bot's token or callback secret.

create or replace function public.erase_interactions_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_interactions bi where bi.user_id = new.id;
  delete from public.bot_ephemeral_messages e where e.user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_interactions_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_interactions on public.profiles;
create trigger profiles_erase_interactions
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_interactions_of_deleted_account();

create or replace function public.export_my_interactions(target_user_id uuid)
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
    'presses', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'sent_at', bi.created_at,
          'kind', bi.kind,
          'bot', b.name,
          'circle', c.name,
          'command', bi.command_name,
          'options', nullif(bi.options, ''),
          'component', bi.component_label,
          'component_type', bi.component_type,
          'values', bi.submitted,
          'answered', bi.responded_at is not null
        ))
        order by bi.created_at desc
      )
      from public.bot_interactions bi
      join public.circle_bots b on b.id = bi.bot_id
      join public.circles c on c.id = bi.circle_id
      where bi.user_id = target_user_id
    ), '[]'::jsonb),
    'private_replies', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'received_at', e.created_at,
          'bot', b.name,
          'text', e.body
        )
        order by e.created_at desc
      )
      from public.bot_ephemeral_messages e
      join public.circle_bots b on b.id = e.bot_id
      where e.user_id = target_user_id
        and e.expires_at > now()
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_interactions(uuid) from public, anon, authenticated;
grant execute on function public.export_my_interactions(uuid) to service_role;
