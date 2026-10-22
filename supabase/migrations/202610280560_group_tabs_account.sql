-- Group tabs (roadmap D8), part 3 of 3: leaving WeCord and taking your data.
--
-- * Deleting an account (profiles.deleted_at) takes the person's name off the
--   tabs they added: the tab belongs to the group and stays, with no
--   creator (the same goes for a pinned message). Same pattern as
--   profiles_erase_events2 (202610270470); prepare_account_deletion is not
--   rewritten.
-- * export_my_group_tabs(user) is for the data-export Edge Function (service
--   role only, like export_my_events2): the tabs I added, with the kind, the
--   title, the link of a link tab and the name of the chat (only while I am
--   still in it).

create or replace function public.erase_group_tabs_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversation_tabs set created_by = null where created_by = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_group_tabs_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_group_tabs on public.profiles;
create trigger profiles_erase_group_tabs
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_group_tabs_of_deleted_account();

create or replace function public.export_my_group_tabs(target_user_id uuid)
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
    'tabs_added', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'kind', t.kind,
          'title', t.title,
          'link', case when t.kind = 'link' then t.target end,
          'chat', case
            when cm.user_id is not null then coalesce(nullif(c.title, ''), c.type)
          end,
          'added_at', t.created_at
        )
        order by t.created_at desc, t.id
      )
      from public.conversation_tabs t
      join public.conversations c on c.id = t.conversation_id
      left join public.conversation_members cm
        on cm.conversation_id = t.conversation_id and cm.user_id = target_user_id
      where t.created_by = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_group_tabs(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_group_tabs(uuid) to service_role;
