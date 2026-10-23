-- Group space (roadmap B6), part 4 of 4: leaving WeCord and taking your data.
--
-- * Deleting an account (the profile gets a deleted_at). The albums, folders,
--   pictures and files of a group belong to the group, as the messages do: what
--   the person put there stays for the others, with the person's name taken off
--   (added_by / created_by become null, which the app shows as "Deleted user").
--   What only the person's own account knew goes: nothing else is held. Same
--   pattern as profiles_erase_events2 (202610270470); prepare_account_deletion
--   is not rewritten. The files stay in the chat buckets under the chat's
--   folder, which is where the person's messages' files stay too.
-- * export_my_group_space(user) is for the data-export Edge Function (service
--   role only, like export_my_events2). What the person added and made, and
--   only that:
--     - albums: the albums they made (name, the group's title while they are
--       still in the group, when);
--     - items: the pictures and videos they added to albums, with the album, a
--       storage path the function signs, the description they wrote;
--     - folders: the folders they made;
--     - files: the files they added, with the folder.
--   Other people's pictures, files and names are not included.

create or replace function public.detach_group_space_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.album_items set added_by = null where added_by = new.id;
  update public.folder_files set added_by = null where added_by = new.id;
  update public.conversation_albums set created_by = null where created_by = new.id;
  update public.conversation_folders set created_by = null where created_by = new.id;
  return new;
end;
$$;

revoke execute on function public.detach_group_space_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_detach_group_space on public.profiles;
create trigger profiles_detach_group_space
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.detach_group_space_of_deleted_account();

create or replace function public.export_my_group_space(target_user_id uuid)
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
    'albums', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', a.name,
          'group', case when m.user_id is not null then c.title end,
          'created_at', a.created_at
        )
        order by a.created_at desc, a.id
      )
      from (
        select * from public.conversation_albums x
        where x.created_by = target_user_id
        order by x.created_at desc, x.id desc
        limit 1000
      ) a
      join public.conversations c on c.id = a.conversation_id
      left join public.conversation_members m
        on m.conversation_id = a.conversation_id and m.user_id = target_user_id
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'album', a.name,
          'group', case when m.user_id is not null then c.title end,
          'kind', i.kind,
          'name', i.name,
          'bucket', i.bucket,
          'path', i.path,
          'size', i.size,
          'description', i.alt,
          'added_at', i.created_at
        ))
        order by i.created_at desc, i.id
      )
      from (
        select * from public.album_items x
        where x.added_by = target_user_id
        order by x.created_at desc, x.id desc
        limit 2000
      ) i
      join public.conversation_albums a on a.id = i.album_id
      join public.conversations c on c.id = i.conversation_id
      left join public.conversation_members m
        on m.conversation_id = i.conversation_id and m.user_id = target_user_id
    ), '[]'::jsonb),
    'folders', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', f.name,
          'group', case when m.user_id is not null then c.title end,
          'created_at', f.created_at
        )
        order by f.created_at desc, f.id
      )
      from (
        select * from public.conversation_folders x
        where x.created_by = target_user_id
        order by x.created_at desc, x.id desc
        limit 1000
      ) f
      join public.conversations c on c.id = f.conversation_id
      left join public.conversation_members m
        on m.conversation_id = f.conversation_id and m.user_id = target_user_id
    ), '[]'::jsonb),
    'files', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'folder', fo.name,
          'group', case when m.user_id is not null then c.title end,
          'kind', ff.kind,
          'name', ff.name,
          'bucket', ff.bucket,
          'path', ff.path,
          'size', ff.size,
          'added_at', ff.created_at
        ))
        order by ff.created_at desc, ff.id
      )
      from (
        select * from public.folder_files x
        where x.added_by = target_user_id
        order by x.created_at desc, x.id desc
        limit 2000
      ) ff
      left join public.conversation_folders fo on fo.id = ff.folder_id
      join public.conversations c on c.id = ff.conversation_id
      left join public.conversation_members m
        on m.conversation_id = ff.conversation_id and m.user_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_group_space(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_group_space(uuid) to service_role;
