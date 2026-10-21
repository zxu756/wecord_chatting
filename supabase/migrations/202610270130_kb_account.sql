-- Circle knowledge base (roadmap D6), part 4 of 4: leaving WeCord and taking
-- your data.
--
-- * Deleting an account (the profile gets a deleted_at; the Edge Function
--   delete-account then removes the login) erases what is only about that
--   person: which pages they read. The pages they wrote stay in the circle,
--   as notes in a conversation do (the profile is anonymised, so the pages
--   show no name); the words they wrote were already part of
--   export_my_extras (the blocks I last wrote in any note, pages included).
--   Same pattern as profiles_erase_notes2 (202610240340);
--   prepare_account_deletion is not rewritten.
-- * export_my_knowledge(user) is for the data-export Edge Function (service
--   role only, like export_my_note_extras): the pages I made, with their
--   circle (the title only while I can still read the page), and which pages
--   I read.

create or replace function public.erase_kb_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_kb_reads where user_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_kb_of_deleted_account() from public, anon, authenticated;

drop trigger if exists profiles_erase_kb on public.profiles;
create trigger profiles_erase_kb
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_kb_of_deleted_account();

create or replace function public.export_my_knowledge(target_user_id uuid)
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
    'pages_made', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'page_id', n.id,
          'circle_id', n.circle_id,
          'circle_name', c.name,
          'title', case
            when public.kb_user_access(n.id, target_user_id) >= 1 then n.title
          end,
          'created_at', n.created_at
        )
        order by n.created_at desc, n.id
      )
      from (
        select *
        from public.notes kn
        where kn.created_by = target_user_id
          and kn.circle_id is not null
          and kn.deleted_at is null
        order by kn.created_at desc, kn.id desc
        limit 2000
      ) n
      join public.circles c on c.id = n.circle_id
    ), '[]'::jsonb),
    'pages_read', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'page_id', r.page_id,
          'circle_id', r.circle_id,
          'circle_name', c.name,
          'title', case
            when public.kb_user_access(r.page_id, target_user_id) >= 1 then n.title
          end,
          'read_at', r.read_at
        )
        order by r.read_at desc, r.page_id
      )
      from (
        select *
        from public.circle_kb_reads kr
        where kr.user_id = target_user_id
        order by kr.read_at desc, kr.page_id desc
        limit 2000
      ) r
      join public.notes n on n.id = r.page_id and n.deleted_at is null
      join public.circles c on c.id = r.circle_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_knowledge(uuid) from public, anon, authenticated;
grant execute on function public.export_my_knowledge(uuid) to service_role;
