-- Edit history (roadmap A2, part 3 of 3): a circle can limit how long a message
-- may be edited.
--
-- * circles.edit_window_seconds: null (the default) is no limit; otherwise
--   15 minutes, 1 hour or 24 hours after the message was sent. Members read it
--   with the rest of the circle (the client selects the column, like
--   circles.ai_enabled).
-- * set_circle_edit_window(circle, seconds): members with manage_circle change
--   it; audited as edit_window_update.
-- * A BEFORE UPDATE OF body trigger refuses an author's edit of a message in
--   one of the circle's channels once the window has passed. edit_message is
--   not redefined, so every way of editing is covered. It leaves alone
--   changes that are not the author's own (the server writing the copies of
--   a published message, where auth.uid() is not the copy's author) and
--   recalls, which do not change the text.
-- * Messages of direct chats and groups are not limited.

alter table public.circles
  add column if not exists edit_window_seconds integer;

alter table public.circles
  drop constraint if exists circles_edit_window_seconds_check;
alter table public.circles
  add constraint circles_edit_window_seconds_check
  check (edit_window_seconds is null or edit_window_seconds in (900, 3600, 86400));

create or replace function public.set_circle_edit_window(
  target_circle_id uuid,
  seconds integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if seconds is not null and seconds not in (900, 3600, 86400) then
    raise exception 'Choose no limit, 15 minutes, 1 hour or 24 hours'
      using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change the edit time limit'
      using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for update;

  if not found then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if circle.edit_window_seconds is not distinct from seconds then
    return circle.edit_window_seconds;
  end if;

  update public.circles c
  set edit_window_seconds = seconds
  where c.id = circle.id;

  perform public.write_circle_audit(
    circle.id,
    'edit_window_update',
    'circle',
    circle.id,
    circle.name,
    jsonb_build_object(
      'edit_window_seconds',
      jsonb_build_object('old', circle.edit_window_seconds, 'new', seconds)
    )
  );

  return seconds;
end;
$$;

revoke execute on function public.set_circle_edit_window(uuid, integer) from public, anon;
grant execute on function public.set_circle_edit_window(uuid, integer) to authenticated;

create or replace function public.messages_enforce_edit_window()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  window_seconds integer;
begin
  if new.body is not distinct from old.body
    or new.recalled_at is not null
    or new.type <> 'text'
    or new.crosspost is not null
    or auth.uid() is null
    or auth.uid() is distinct from new.sender_id
  then
    return new;
  end if;

  select c.edit_window_seconds into window_seconds
  from public.circle_channels cc
  join public.circles c on c.id = cc.circle_id
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);

  if window_seconds is not null
    and now() > old.created_at + make_interval(secs => window_seconds)
  then
    raise exception 'The time to edit this message has passed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_enforce_edit_window() from public, anon, authenticated;

-- A refused edit rolls the whole statement back, so no version is kept for it
-- (messages_edit_history also fires on this update).
drop trigger if exists messages_enforce_edit_window on public.messages;
create trigger messages_enforce_edit_window
  before update of body on public.messages
  for each row execute function public.messages_enforce_edit_window();
