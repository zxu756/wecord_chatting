-- Favorites 2.0 (roadmap B3), part 4 of 4: taking your data.
--
-- "Download my data" (202610170053, 202610190023): export_my_saved_items(user)
-- is for the data-export Edge Function (service role only, like
-- export_my_forms). It returns the person's folders and everything they kept,
-- with where it is filed, its tags and remark. The text of a message, Moment
-- or post is included only when the person wrote it (the same rule as
-- saved_messages.json): somebody else's words are not copied into the export.
-- Links, notes and text are the person's own and come whole, with the files of
-- note pictures named by bucket and path so the export can link them.
--
-- A new function: export_my_extras is not rewritten (its saved_messages part
-- keeps working through the saved_messages view). Capped at 1000 entries.

create or replace function public.export_my_saved_items(target_user_id uuid)
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
    'folders', coalesce((
      select jsonb_agg(
        jsonb_build_object('id', f.id, 'name', f.name, 'created_at', f.created_at)
        order by f.created_at, f.id
      )
      from public.saved_folders f
      where f.user_id = target_user_id
    ), '[]'::jsonb),
    'items', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id', s.id,
          'kind', s.kind,
          'target_id', s.target_id,
          'conversation_id', s.conversation_id,
          'circle_id', s.circle_id,
          'folder', s.folder_name,
          'tags', to_jsonb(s.tags),
          'remark', s.note,
          'saved_at', s.created_at,
          'done_at', s.done_at,
          'from_you', case
            when s.kind = 'moment' then s.moment_author = target_user_id
            when s.kind = 'circle_post' then s.post_author = target_user_id
            when s.kind = 'message' then s.message_sender = target_user_id
          end,
          'text', case
            when s.kind = 'moment' and s.moment_author = target_user_id then s.moment_body
            when s.kind = 'circle_post' and s.post_author = target_user_id then s.post_body
            when s.kind = 'message' and s.message_sender = target_user_id then s.message_body
          end,
          'title', s.title,
          'body', s.body,
          'url', s.url,
          'images', case
            when s.kind = 'note' then (
              select coalesce(jsonb_agg(
                jsonb_build_object('bucket', 'saved-notes', 'path', i->>'path')
              ), '[]'::jsonb)
              from jsonb_array_elements(s.images) i
            )
          end
        ))
        order by s.created_at desc, s.id
      )
      from (
        select si.*,
               f.name as folder_name,
               mp.author_id as moment_author, mp.body as moment_body,
               cp.author_id as post_author, cp.body as post_body,
               m.sender_id as message_sender, m.body as message_body
        from public.saved_items si
        left join public.saved_folders f on f.id = si.folder_id
        left join public.moments_posts mp
          on si.kind = 'moment' and mp.id = si.target_id
        left join public.circle_posts cp
          on si.kind = 'circle_post' and cp.id = si.target_id
        left join public.messages m
          on si.kind = 'message' and m.id = si.target_id
        where si.user_id = target_user_id
        order by si.created_at desc, si.id desc
        limit 1000
      ) s
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_saved_items(uuid) from public;
revoke execute on function public.export_my_saved_items(uuid) from anon;
revoke execute on function public.export_my_saved_items(uuid) from authenticated;
