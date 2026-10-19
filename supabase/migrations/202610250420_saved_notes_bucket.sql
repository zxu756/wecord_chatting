-- Favorites 2.0 (roadmap B3), part 3 of 4: the pictures of the person's own
-- notes.
--
-- The bucket "saved-notes" is PRIVATE: 5 MB a file, JPEG only (the app
-- scales and re-encodes, which also drops the metadata). Objects are named
-- <user id>/<entry id>-<0..3>.jpg, where the entry is the saved_items row the
-- picture belongs to. Only the owner reads, writes and removes their folder,
-- and there is no way to share a file: a note is for its owner alone, so no
-- other rule reads it. At most 4000 files a person (1000 entries, 4 pictures).
--
-- The files of a removed entry are removed by the app together with it. The
-- delete-account function empties the whole folder when the account goes
-- (userBuckets).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'saved-notes',
  'saved-notes',
  false,
  5242880,
  array['image/jpeg']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- How many files the caller has. A function, because a policy on
-- storage.objects that counts storage.objects itself recurses.
create or replace function public.saved_note_file_count()
returns integer
language sql
stable
security definer
set search_path = public, storage
as $$
  select count(*)::integer
  from storage.objects o
  where o.bucket_id = 'saved-notes'
    and o.name like auth.uid()::text || '/%';
$$;

revoke execute on function public.saved_note_file_count() from public, anon;
grant execute on function public.saved_note_file_count() to authenticated;

drop policy if exists saved_notes_select_owner on storage.objects;
create policy saved_notes_select_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'saved-notes'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists saved_notes_insert_owner on storage.objects;
create policy saved_notes_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'saved-notes'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-3]\.jpg$'
    and public.saved_note_file_count() < 4000
  );

drop policy if exists saved_notes_delete_owner on storage.objects;
create policy saved_notes_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'saved-notes'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
