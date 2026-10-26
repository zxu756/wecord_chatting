-- Advanced chat privacy (G6) and screenshot alerts (G7), part 4 of 4:
-- deleting an account, and taking your data.
--
-- * Deleting an account (profiles.deleted_at) erases the person's screenshot
--   reports (message_view_once_screenshots) and takes their id out of the
--   requests of the chats they asked to restrict: a direct chat stays
--   restricted only if the other person asked too, a group keeps the switch an
--   admin turned on (it was the group's, not the person's). The lines the
--   chat already shows ("Ada took a screenshot ...", "Ada turned on advanced
--   chat privacy") stay, as other chat notices do. prepare_account_deletion is
--   not rewritten (same pattern as profiles_erase_events2, 202610270470).
-- * restricted_conversation_ids(ids) is for the data-export Edge function
--   (service role only): which of the chats are restricted, threads included.
--   The export keeps those chats' messages out of the archive; it says so.
-- * export_my_chat_privacy(user) is for the same function (service role
--   only): the chats the person asked to restrict, and the screenshot reports
--   they caused. Nothing about other people's requests or reports.

create or replace function public.erase_chat_privacy_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.message_view_once_screenshots s where s.user_id = new.id;

  update public.conversations c
  set restrict_sharing_by = array_remove(c.restrict_sharing_by, new.id),
      restrict_sharing = case
        when c.type = 'direct'
          then cardinality(array_remove(c.restrict_sharing_by, new.id)) > 0
        else c.restrict_sharing
      end
  where new.id = any (c.restrict_sharing_by);
  return new;
end;
$$;

revoke execute on function public.erase_chat_privacy_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_chat_privacy on public.profiles;
create trigger profiles_erase_chat_privacy
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_chat_privacy_of_deleted_account();

create or replace function public.restricted_conversation_ids(p_ids uuid[])
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(x), '{}'::uuid[])
  from unnest(coalesce(p_ids, '{}'::uuid[])) as x
  where public.conversation_restricts_sharing(x);
$$;

revoke execute on function public.restricted_conversation_ids(uuid[])
  from public, anon, authenticated;
grant execute on function public.restricted_conversation_ids(uuid[])
  to service_role;

create or replace function public.export_my_chat_privacy(target_user_id uuid)
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
    'requested_in', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conversation_id', c.id,
          'kind', c.type,
          'restricted_now', c.restrict_sharing
        )
        order by c.created_at, c.id
      )
      from public.conversations c
      where target_user_id = any (c.restrict_sharing_by)
    ), '[]'::jsonb),
    'screenshot_reports', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'reported_at', s.created_at,
          'event', s.event,
          'conversation_id', s.conversation_id
        )
        order by s.created_at, s.message_id
      )
      from public.message_view_once_screenshots s
      where s.user_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_chat_privacy(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_chat_privacy(uuid)
  to service_role;
