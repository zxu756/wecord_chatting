-- Events 2.0 (roadmap C10), part 6 of 7: the photos of an event.
--
-- The event gathers its own pictures, so they are not scattered through the
-- chat afterwards: people who took part add them from the event, and anyone who
-- can see the event can look through them. (The group albums of B6 do not exist
-- yet; when they do, an event's pictures can be offered to them.)
--
-- * add_event_photo(kind, event, path): a picture already uploaded to Storage.
--   A chat event's pictures live in the chat-images bucket under the
--   conversation's folder (<conversation id>/...), a circle event's in chat-media
--   under the circle's (<circle id>/...): the same places those chats keep
--   their pictures, with the same readers. Who: someone who signed up (Going or
--   Maybe in a chat, signed up in a circle) or checked in. When: from an hour
--   before the start until two weeks after the end. At most 20 per person and
--   300 per event. The file has to be there already.
-- * list_event_photos(kind, event): newest first, up to 300, for anyone who can
--   see the event; pictures of somebody who blocked the viewer or whom the
--   viewer blocked are left out.
-- * delete_event_photo(photo): the person who added it, or an organiser. The
--   row goes; the app also removes the file.
-- A circle an admin suspended takes no new picture (K1); a suspended account
-- adds none.

create or replace function public.add_event_photo(
  p_kind text,
  p_event_id uuid,
  p_path text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  scope record;
  photo_bucket text;
  attended boolean;
  new_row public.event_photos%rowtype;
begin
  select * into scope from public.events2_event_scope(p_kind, p_event_id, 'member');
  if scope.cancelled_at is not null then
    raise exception 'This event was cancelled' using errcode = '22023';
  end if;
  if now() < scope.starts_at - interval '1 hour'
    or now() > scope.effective_ends_at + interval '14 days'
  then
    raise exception 'Pictures can be added from the start of the event until two weeks after'
      using errcode = '22023';
  end if;

  photo_bucket := case when p_kind = 'chat' then 'chat-images' else 'chat-media' end;
  if p_path is null
    or char_length(p_path) not between 3 and 300
    or p_path ~ '\.\.'
    or p_path not like scope.scope_id::text || '/%'
  then
    raise exception 'The picture must be in the % folder',
      case when p_kind = 'chat' then 'chat''s' else 'circle''s' end
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = photo_bucket and o.name = p_path
  ) then
    raise exception 'Upload the picture first' using errcode = '22023';
  end if;

  attended := exists (
    select 1 from public.event_check_ins ci
    where ci.user_id = current_user_id
      and ((p_kind = 'chat' and ci.chat_event_id = p_event_id)
        or (p_kind = 'circle' and ci.circle_event_id = p_event_id))
  ) or (p_kind = 'chat' and exists (
    select 1 from public.chat_event_rsvps r
    where r.event_id = p_event_id and r.user_id = current_user_id
      and r.status in ('going', 'maybe')
  )) or (p_kind = 'circle' and exists (
    select 1 from public.circle_event_rsvps r
    where r.event_id = p_event_id and r.user_id = current_user_id
  ));
  if not attended then
    raise exception 'Only people who signed up or checked in can add pictures'
      using errcode = '42501';
  end if;

  if (
    select count(*) from public.event_photos ph
    where ph.user_id = current_user_id
      and ((p_kind = 'chat' and ph.chat_event_id = p_event_id)
        or (p_kind = 'circle' and ph.circle_event_id = p_event_id))
  ) >= 20 then
    raise exception 'You can add up to 20 pictures to an event' using errcode = '22023';
  end if;
  if (
    select count(*) from public.event_photos ph
    where (p_kind = 'chat' and ph.chat_event_id = p_event_id)
      or (p_kind = 'circle' and ph.circle_event_id = p_event_id)
  ) >= 300 then
    raise exception 'This event has all the pictures it can hold' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.event_photos ph
    where ph.bucket = photo_bucket and ph.path = p_path
  ) then
    raise exception 'That picture is already added' using errcode = '22023';
  end if;

  insert into public.event_photos (chat_event_id, circle_event_id, user_id, bucket, path)
  values (
    case when p_kind = 'chat' then p_event_id end,
    case when p_kind = 'circle' then p_event_id end,
    current_user_id, photo_bucket, p_path
  )
  returning * into new_row;

  return jsonb_build_object(
    'id', new_row.id,
    'bucket', new_row.bucket,
    'path', new_row.path,
    'user_id', new_row.user_id,
    'created_at', new_row.created_at,
    'mine', true,
    'can_delete', true
  );
end;
$$;

create or replace function public.list_event_photos(
  p_kind text,
  p_event_id uuid
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  scope record;
  organiser boolean;
begin
  select * into scope from public.events2_event_scope(p_kind, p_event_id, 'read');
  organiser := case
    when p_kind = 'chat' then exists (
      select 1 from public.chat_events e
      where e.id = p_event_id and public.can_manage_chat_event(e, current_user_id)
    )
    else exists (
      select 1 from public.circle_events e
      where e.id = p_event_id
        and (e.created_by is not distinct from current_user_id
          or public.current_user_has_circle_permission(e.circle_id, 'manage_events'))
    )
  end;

  return query
  select jsonb_build_object(
    'id', ph.id,
    'bucket', ph.bucket,
    'path', ph.path,
    'user_id', ph.user_id,
    'uploader_name', case
      when p_kind = 'circle' then coalesce(public.circle_member_label(scope.scope_id, ph.user_id), p.display_name)
      else coalesce(nullif(btrim(p.display_name), ''), p.username)
    end,
    'created_at', ph.created_at,
    'mine', ph.user_id = current_user_id,
    'can_delete', ph.user_id = current_user_id or organiser
  )
  from public.event_photos ph
  join public.profiles p on p.id = ph.user_id
  where ((p_kind = 'chat' and ph.chat_event_id = p_event_id)
      or (p_kind = 'circle' and ph.circle_event_id = p_event_id))
    and not public.are_users_blocked(current_user_id, ph.user_id)
  order by ph.created_at desc, ph.id
  limit 300;
end;
$$;

create or replace function public.delete_event_photo(p_photo_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  photo public.event_photos%rowtype;
  kind_value text;
  event_value uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into photo from public.event_photos ph where ph.id = p_photo_id;
  if photo.id is null then
    return;
  end if;
  kind_value := case when photo.chat_event_id is not null then 'chat' else 'circle' end;
  event_value := coalesce(photo.chat_event_id, photo.circle_event_id);

  -- The owner can always take their own picture back; anybody else must be an
  -- organiser of the event.
  if photo.user_id <> current_user_id then
    perform 1 from public.events2_event_scope(kind_value, event_value, 'manage');
  else
    perform 1 from public.events2_event_scope(kind_value, event_value, 'read');
  end if;

  delete from public.event_photos ph where ph.id = p_photo_id;
end;
$$;

revoke execute on function public.add_event_photo(text, uuid, text) from public, anon;
revoke execute on function public.list_event_photos(text, uuid) from public, anon;
revoke execute on function public.delete_event_photo(uuid) from public, anon;
grant execute on function public.add_event_photo(text, uuid, text) to authenticated;
grant execute on function public.list_event_photos(text, uuid) to authenticated;
grant execute on function public.delete_event_photo(uuid) to authenticated;
