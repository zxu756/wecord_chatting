-- Whiteboard (roadmap D10), part 6 of 6: leaving WeCord and taking your data.
--
-- * Deleting an account (profiles.deleted_at; the Edge Function
--   delete-account then removes the login) takes the person's name off the
--   whiteboards: a board and what is drawn on it belong to the chat and stay,
--   as notes do, but nothing points at the person any more (the creator and
--   the last editor of the boards, the last editor of each element, the
--   author of a version). The pictures of a board sit in the board's own
--   folder of the whiteboard-files bucket, not in a folder named after the
--   person, so there is nothing to remove from the user buckets.
--   Same pattern as profiles_erase_group_tabs (202610280560);
--   prepare_account_deletion is not rewritten.
-- * export_my_whiteboards(user) is for the data-export Edge Function (service
--   role only, like export_my_group_tabs): the boards I made, and, for each
--   board of a chat I am still in, what I last drew or wrote on it: how many
--   strokes, shapes, sticky notes, texts and pictures, and the words of my
--   sticky notes and texts. Nobody else's drawing, and nothing from a chat I
--   have left.

create or replace function public.erase_whiteboards_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.whiteboards set created_by = null where created_by = new.id;
  update public.whiteboards set updated_by = null where updated_by = new.id;
  update public.whiteboard_elements set updated_by = null where updated_by = new.id;
  update public.whiteboard_versions set created_by = null where created_by = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_whiteboards_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_whiteboards on public.profiles;
create trigger profiles_erase_whiteboards
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_whiteboards_of_deleted_account();

create or replace function public.export_my_whiteboards(target_user_id uuid)
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
    'boards_made', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'title', w.title,
          'chat', case
            when cm.user_id is not null then coalesce(nullif(c.title, ''), c.type)
          end,
          'elements', w.element_count,
          'created_at', w.created_at
        )
        order by w.created_at desc, w.id
      )
      from public.whiteboards w
      join public.conversations c on c.id = w.conversation_id
      left join public.conversation_members cm
        on cm.conversation_id = w.conversation_id and cm.user_id = target_user_id
      where w.created_by = target_user_id and w.deleted_at is null
    ), '[]'::jsonb),
    'drawn_on', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'board', b.title,
          'chat', b.chat,
          'strokes', b.strokes,
          'shapes', b.shapes,
          'sticky_notes', b.stickies,
          'texts', b.texts,
          'pictures', b.pictures,
          'words', b.words
        )
        order by b.title, b.board_id
      )
      from (
        select
          w.id as board_id,
          w.title,
          coalesce(nullif(c.title, ''), c.type) as chat,
          count(*) filter (where e.kind = 'stroke') as strokes,
          count(*) filter (where e.kind = 'shape') as shapes,
          count(*) filter (where e.kind = 'sticky') as stickies,
          count(*) filter (where e.kind = 'text') as texts,
          count(*) filter (where e.kind = 'image') as pictures,
          coalesce(
            jsonb_agg(e.data ->> 't' order by e.z, e.id)
              filter (where e.kind in ('sticky', 'text') and coalesce(e.data ->> 't', '') <> ''),
            '[]'::jsonb
          ) as words
        from public.whiteboard_elements e
        join public.whiteboards w on w.id = e.board_id and w.deleted_at is null
        join public.conversations c on c.id = w.conversation_id
        join public.conversation_members cm
          on cm.conversation_id = w.conversation_id and cm.user_id = target_user_id
        where e.updated_by = target_user_id and not e.deleted
        group by w.id, w.title, c.title, c.type
        limit 500
      ) b
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_whiteboards(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_whiteboards(uuid) to service_role;
