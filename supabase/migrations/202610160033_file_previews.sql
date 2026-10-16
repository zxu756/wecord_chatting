-- PDF previews of Office files, for the web viewer.
--
-- * Bucket file-previews (private) holds the PDF the office-preview Edge
--   Function converted (through Gotenberg) from a file message, at
--   <message id>/preview.pdf. Only the service role writes there.
-- * Anyone who can see the message may read its preview: the policy looks
--   the message up as the caller, so the messages table's own row level
--   security decides (members of the conversation). A deleted message's
--   preview stops being readable at once.
-- * Clean-up: Storage objects can't be deleted from SQL, so
--   stale_file_previews() lists previews whose message is gone, deleted or
--   no longer a file, and the office-preview function removes a few of
--   them (service role) on each call. Previews of deleted conversations
--   and channels go the same way, since their messages are gone.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('file-previews', 'file-previews', false, 104857600, array['application/pdf'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- The message id a preview object belongs to, or null for any other name.
create or replace function public.file_preview_message_id(object_name text)
returns uuid
language sql
immutable
set search_path = public
as $$
  select case
    when (storage.foldername(object_name))[1]
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(object_name))[1])::uuid
  end;
$$;

drop policy if exists file_previews_select_visible on storage.objects;
create policy file_previews_select_visible
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'file-previews'
    and exists (
      -- Runs as the caller: messages' row level security applies.
      select 1
      from public.messages m
      where m.id = public.file_preview_message_id(objects.name)
        and m.type = 'file'
        and m.recalled_at is null
        and m.attachment is not null
    )
  );

-- Previews whose message no longer shows a file, oldest first, for the
-- office-preview function to remove.
create or replace function public.stale_file_previews(max_rows integer default 20)
returns table (object_name text)
language sql
stable
security definer
set search_path = public
as $$
  select o.name
  from storage.objects o
  where o.bucket_id = 'file-previews'
    and not exists (
      select 1
      from public.messages m
      where m.id = public.file_preview_message_id(o.name)
        and m.type = 'file'
        and m.recalled_at is null
        and m.attachment is not null
    )
  order by o.created_at
  limit greatest(1, least(coalesce(max_rows, 20), 100));
$$;

revoke execute on function public.stale_file_previews(integer) from public;
revoke execute on function public.stale_file_previews(integer) from anon;
revoke execute on function public.stale_file_previews(integer) from authenticated;
grant execute on function public.stale_file_previews(integer) to service_role;
