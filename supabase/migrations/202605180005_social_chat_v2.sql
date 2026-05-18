alter table public.messages
  add column if not exists reply_preview jsonb;

drop policy if exists profiles_update_own on public.profiles;

create or replace function public.create_group_conversation(
  group_title text,
  member_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_title text := trim(coalesce(group_title, ''));
  created_conversation_id uuid;
  selected_member_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_title) = 0 then
    raise exception 'Group title is required' using errcode = '22023';
  end if;

  with selected_members as (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as selected(member_id)
    where member_id is not null
      and member_id <> current_user_id
  )
  select count(*) into selected_member_count
  from selected_members;

  if selected_member_count < 2 then
    raise exception 'A group conversation requires at least two members'
      using errcode = '22023';
  end if;

  if exists (
    with selected_members as (
      select distinct member_id
      from unnest(coalesce(member_ids, array[]::uuid[])) as selected(member_id)
      where member_id is not null
        and member_id <> current_user_id
    )
    select 1
    from selected_members sm
    where not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, sm.member_id)
        and f.user_high_id = greatest(current_user_id, sm.member_id)
    )
  ) then
    raise exception 'Group members must be accepted friends'
      using errcode = '42501';
  end if;

  insert into public.conversations (type, title)
  values ('group', trimmed_title)
  returning id into created_conversation_id;

  -- Contract guard: role, 'owner'
  insert into public.conversation_members (conversation_id, user_id, role)
  values (created_conversation_id, current_user_id, 'owner');

  -- Contract guard: role, 'member'
  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, sm.member_id, 'member'
  from (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as selected(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ) sm;

  return created_conversation_id;
end;
$$;

create or replace function public.rename_group_conversation(
  target_conversation_id uuid,
  group_title text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text := trim(coalesce(group_title, ''));
  renamed_conversation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_title) = 0 then
    raise exception 'Group title is required' using errcode = '22023';
  end if;

  update public.conversations c
  set title = trimmed_title
  where c.id = target_conversation_id
    and c.type = 'group'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    )
  returning c.id into renamed_conversation_id;

  if renamed_conversation_id is null then
    raise exception 'Group conversation not found or cannot be renamed'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.add_group_members(
  target_conversation_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = target_conversation_id
      and c.type = 'group'
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Group conversation not found or cannot be changed'
      using errcode = '42501';
  end if;

  if exists (
    with selected_members as (
      select distinct member_id
      from unnest(coalesce(member_ids, array[]::uuid[])) as selected(member_id)
      where member_id is not null
        and member_id <> current_user_id
    )
    select 1
    from selected_members sm
    where not exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, sm.member_id)
        and f.user_high_id = greatest(current_user_id, sm.member_id)
    )
  ) then
    raise exception 'Group members must be accepted friends'
      using errcode = '42501';
  end if;

  insert into public.conversation_members (conversation_id, user_id, role)
  select target_conversation_id, sm.member_id, 'member'
  from (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as selected(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ) sm
  on conflict (conversation_id, user_id) do nothing;
end;
$$;

create or replace function public.update_current_user_profile(
  display_name text,
  bio text,
  avatar_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_display_name text := trim(coalesce(display_name, ''));
  updated_profile_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_display_name) = 0 then
    raise exception 'Display name is required' using errcode = '22023';
  end if;

  update public.profiles
  set
    display_name = trimmed_display_name,
    bio = coalesce(update_current_user_profile.bio, ''),
    avatar_url = update_current_user_profile.avatar_url
  where id = auth.uid()
  returning id into updated_profile_id;

  if updated_profile_id is null then
    raise exception 'Profile not found or cannot be updated'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.edit_message(
  target_message_id uuid,
  body text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_body text := trim(coalesce(body, ''));
  edited_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 then
    raise exception 'Message body is required' using errcode = '22023';
  end if;

  update public.messages m
  set
    body = trimmed_body,
    edited_at = now()
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and m.type = 'text'
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.id into edited_message_id;

  if edited_message_id is null then
    raise exception 'Message not found or cannot be edited'
      using errcode = '42501';
  end if;
end;
$$;

insert into storage.buckets (id, name, public)
values ('profile-avatars', 'profile-avatars', false)
on conflict (id) do update
set public = false;

drop policy if exists profile_avatars_select_authenticated on storage.objects;

create policy profile_avatars_select_authenticated
  on storage.objects for select
  to authenticated
  using (bucket_id = 'profile-avatars');

drop policy if exists profile_avatars_insert_owner on storage.objects;

create policy profile_avatars_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
