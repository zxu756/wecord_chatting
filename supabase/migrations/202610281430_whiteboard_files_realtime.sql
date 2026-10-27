-- Whiteboard (roadmap D10), part 4 of 6: pictures and the live channel.
--
-- Pictures. Bucket whiteboard-files (private, pictures up to 5 MB) holds the
-- pictures put on a board, at <board id>/<file>, like note-files does for a
-- note. The app scales a picture down before it uploads it.
--   * read: anyone who can see the board;
--   * upload: anyone who can draw on it, up to 60 pictures per board;
--   * remove: the creator or a manager, once the board is deleted
--     (delete_whiteboard lists the files). A picture that was rubbed out
--     stays, so "undo" can bring it back.
-- A picture can only be put on a board with a path inside that board's own
-- folder (whiteboard_apply_ops checks it).
--
-- The live channel. Who is on a board and where their pointer is, and the
-- stroke someone is drawing right now, travel over a private Realtime channel
-- named whiteboard-live-<board id>:
--   * listening, and showing oneself (presence): anyone who can see the board
--     (so: its chat's members), not while the other person of a direct chat
--     is blocked, not once the board is deleted;
--   * sending live strokes and pointer moves (broadcast): only whoever can
--     draw on the board. Nothing sent here is stored: the stroke itself
--     reaches everyone through whiteboard_apply_ops when the pen is lifted.
-- Anything else stays refused.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'whiteboard-files', 'whiteboard-files', false, 5242880,
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The board a storage path belongs to (<board id>/<file>), or null.
create or replace function public.whiteboard_file_board_id(object_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when object_name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/[^/]+$'
      then split_part(object_name, '/', 1)::uuid
  end;
$$;

-- Whether the current user may add a picture to the board: they can draw on
-- it and it has fewer than 60.
create or replace function public.can_current_user_upload_whiteboard_file(
  target_board_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_board_id is not null
    and public.can_current_user_edit_whiteboard(target_board_id)
    and (
      select count(*)
      from storage.objects o
      where o.bucket_id = 'whiteboard-files'
        and o.name like target_board_id::text || '/%'
    ) < 60;
$$;

-- Whether the current user may remove a board's pictures: the board is
-- deleted and they are its author or manage the conversation.
create or replace function public.can_current_user_delete_whiteboard_files(
  target_board_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  w public.whiteboards%rowtype;
begin
  if auth.uid() is null or target_board_id is null then
    return false;
  end if;
  select * into w from public.whiteboards where id = target_board_id;
  return w.id is not null
    and w.deleted_at is not null
    and public.is_current_user_conversation_member(w.conversation_id)
    and (
      w.created_by = auth.uid()
      or public.can_current_user_moderate_messages(w.conversation_id)
    );
end;
$$;

revoke execute on function public.whiteboard_file_board_id(text) from public, anon;
revoke execute on function public.can_current_user_upload_whiteboard_file(uuid) from public, anon;
revoke execute on function public.can_current_user_delete_whiteboard_files(uuid) from public, anon;
grant execute on function public.whiteboard_file_board_id(text) to authenticated;
grant execute on function public.can_current_user_upload_whiteboard_file(uuid) to authenticated;
grant execute on function public.can_current_user_delete_whiteboard_files(uuid) to authenticated;

drop policy if exists whiteboard_files_select_member on storage.objects;
create policy whiteboard_files_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'whiteboard-files'
    and public.whiteboard_file_board_id(name) is not null
    and public.can_current_user_view_whiteboard(public.whiteboard_file_board_id(name))
  );

drop policy if exists whiteboard_files_insert_editor on storage.objects;
create policy whiteboard_files_insert_editor
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'whiteboard-files'
    and public.whiteboard_file_board_id(name) is not null
    and public.can_current_user_upload_whiteboard_file(public.whiteboard_file_board_id(name))
  );

drop policy if exists whiteboard_files_delete_deleted_board on storage.objects;
create policy whiteboard_files_delete_deleted_board
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'whiteboard-files'
    and public.can_current_user_delete_whiteboard_files(public.whiteboard_file_board_id(name))
  );

-- ------------------------------------------------------------ live channel

-- Who is on a board, and where their pointer is: viewers.
create or replace function public.can_use_whiteboard_live(target_board_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select target_board_id is not null
    and auth.uid() is not null
    and public.can_current_user_view_whiteboard(target_board_id)
    and exists (
      select 1
      from public.whiteboards w
      where w.id = target_board_id
        and w.deleted_at is null
        and not public.is_current_user_blocked_in_conversation(w.conversation_id)
    );
$$;

-- Live strokes and pointer moves: only whoever can draw.
create or replace function public.can_send_whiteboard_live(target_board_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_use_whiteboard_live(target_board_id)
    and public.can_current_user_edit_whiteboard(target_board_id);
$$;

revoke execute on function public.can_use_whiteboard_live(uuid) from public, anon;
revoke execute on function public.can_send_whiteboard_live(uuid) from public, anon;
grant execute on function public.can_use_whiteboard_live(uuid) to authenticated;
grant execute on function public.can_send_whiteboard_live(uuid) to authenticated;

-- Listen: presence and broadcast, for viewers.
drop policy if exists whiteboard_live_receive on realtime.messages;
create policy whiteboard_live_receive
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_use_whiteboard_live(
      public.realtime_topic_uuid((select realtime.topic()), 'whiteboard-live-')
    )
  );

-- Send: show oneself (any viewer), broadcast (whoever can draw).
drop policy if exists whiteboard_live_send on realtime.messages;
create policy whiteboard_live_send
  on realtime.messages for insert
  to authenticated
  with check (
    (
      realtime.messages.extension = 'presence'
      and public.can_use_whiteboard_live(
        public.realtime_topic_uuid((select realtime.topic()), 'whiteboard-live-')
      )
    )
    or (
      realtime.messages.extension = 'broadcast'
      and public.can_send_whiteboard_live(
        public.realtime_topic_uuid((select realtime.topic()), 'whiteboard-live-')
      )
    )
  );
