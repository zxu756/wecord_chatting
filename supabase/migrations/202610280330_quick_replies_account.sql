-- Quick replies, the away auto-reply and round video messages (roadmap A8 and
-- A13), last part: deleting an account, and taking your data.
--
-- * Deleting an account (profiles.deleted_at) erases the quick replies, turns
--   the auto-reply off and forgets its message, and drops the log of who was
--   answered (both as the away person and as the one answered). Same pattern as
--   profiles_erase_events2 (202610270470): prepare_account_deletion is not
--   rewritten. The messages themselves, auto-replies included, go with the
--   rest of the person's messages. Round video messages are ordinary video
--   file messages in the existing chat-files bucket, handled exactly like the
--   person's other videos when their messages go, so no bucket is added.
-- * export_my_quick_replies(user) is for the data-export Edge Function (service
--   role only, like export_my_events2): the person's quick replies and their
--   auto-reply settings. Nobody else's data is in it. The auto-replies the
--   person sent and the round videos they made are messages and attachments,
--   which the export already holds.

create or replace function public.erase_quick_replies_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.quick_replies where user_id = new.id;
  update public.user_notification_settings
  set away_enabled = false,
      away_message = null,
      away_until = null,
      away_in_quiet_hours = false
  where user_id = new.id
    and (
      away_enabled
      or away_message is not null
      or away_until is not null
      or away_in_quiet_hours
    );
  delete from public.away_reply_log
  where away_user_id = new.id or to_user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_quick_replies_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_quick_replies on public.profiles;
create trigger profiles_erase_quick_replies
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_quick_replies_of_deleted_account();

create or replace function public.export_my_quick_replies(target_user_id uuid)
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
    'quick_replies', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'shortcut', q.shortcut,
          'body', q.body,
          'created_at', q.created_at,
          'updated_at', q.updated_at
        )
        order by q.created_at
      )
      from public.quick_replies q
      where q.user_id = target_user_id
    ), '[]'::jsonb),
    'away', (
      select jsonb_build_object(
        'enabled', s.away_enabled,
        'message', s.away_message,
        'until', s.away_until,
        'during_quiet_hours', s.away_in_quiet_hours
      )
      from public.user_notification_settings s
      where s.user_id = target_user_id
        and (
          s.away_enabled
          or s.away_message is not null
          or s.away_in_quiet_hours
        )
    )
  );
end;
$$;

revoke execute on function public.export_my_quick_replies(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_quick_replies(uuid) to service_role;
