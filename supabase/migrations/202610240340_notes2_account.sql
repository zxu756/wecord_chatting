-- Notes 2.0 (roadmap D5), part 5 of 5: leaving WeCord and taking your data.
--
-- * Deleting an account (the profile gets a deleted_at; the Edge Function
--   delete-account then removes the login) erases what the person wrote in
--   notes 2.0 and what only they could use: their comments (and the replies
--   under them), their personal templates, the pages they published (the
--   links stop working), and the notifications they were sent. Same pattern
--   as profiles_erase_edit_history (202610220210). prepare_account_deletion
--   is not rewritten.
-- * export_my_note_extras(user) is for the data-export Edge Function (service
--   role only, like export_my_forms): the comments I wrote (with the note's
--   title and the words they were made on), my personal templates, and the
--   pages I published (no link: it is a credential). Only my own words - what
--   others wrote in the same threads is not included. The tables I wrote in
--   notes are already in export_my_extras (their cells are block props).
--
-- New functions only; export_my_extras is not rewritten.

create or replace function public.erase_notes2_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.note_comments where author_id = new.id;
  delete from public.note_templates where owner_id = new.id;
  delete from public.note_publications where published_by = new.id;
  delete from public.note_comment_notifications where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_notes2_of_deleted_account() from public, anon, authenticated;

drop trigger if exists profiles_erase_notes2 on public.profiles;
create trigger profiles_erase_notes2
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_notes2_of_deleted_account();

create or replace function public.export_my_note_extras(target_user_id uuid)
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
    'comments', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.id,
          'note_id', c.note_id,
          'note_title', n.title,
          'reply', c.parent_id is not null,
          'quoted', c.anchor_text,
          'body', c.body,
          'created_at', c.created_at,
          'edited_at', c.edited_at,
          'resolved', c.resolved_at is not null
        )
        order by c.created_at desc, c.id
      )
      from (
        select *
        from public.note_comments nc
        where nc.author_id = target_user_id
        order by nc.created_at desc, nc.id desc
        limit 2000
      ) c
      join public.notes n on n.id = c.note_id and n.deleted_at is null
    ), '[]'::jsonb),
    'templates', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', t.id,
          'name', t.name,
          'icon', t.icon,
          'title', t.title,
          'blocks', t.blocks,
          'created_at', t.created_at
        )
        order by t.created_at desc, t.id
      )
      from public.note_templates t
      where t.owner_id = target_user_id
    ), '[]'::jsonb),
    'published', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'note_id', pub.note_id,
          'note_title', n.title,
          'published_at', pub.published_at,
          'allow_indexing', pub.allow_indexing
        )
        order by pub.published_at desc, pub.note_id
      )
      from public.note_publications pub
      join public.notes n on n.id = pub.note_id and n.deleted_at is null
      where pub.published_by = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_note_extras(uuid) from public, anon, authenticated;
grant execute on function public.export_my_note_extras(uuid) to service_role;
