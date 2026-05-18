drop function if exists public.list_conversation_summaries();

alter table public.messages
  add column if not exists forwarded_from jsonb;

create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[]
)
language sql
stable
security definer
set search_path = public
as $$
  with current_memberships as (
    select
      cm.conversation_id,
      cm.last_read_message_id,
      cm.pinned_at,
      cm.muted_until,
      cm.hidden_at,
      cm.manual_unread_at
    from public.conversation_members cm
    where cm.user_id = auth.uid()
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url
    from public.conversation_members cm
    join public.profiles p on p.id = cm.user_id
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where cm.user_id <> auth.uid()
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    group by mm.message_id
  )
  select
    c.id,
    c.type,
    coalesce(c.title, dp.display_name) as title,
    coalesce(c.avatar_url, dp.avatar_url) as avatar_url,
    c.announcement,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    greatest(
      count(unread_messages.id),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  left join public.messages unread_messages
    on unread_messages.conversation_id = c.id
    and unread_messages.sender_id <> auth.uid()
    and (
      rm.last_read_at is null
      or unread_messages.created_at > rm.last_read_at
    )
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  group by
    c.id,
    c.type,
    c.title,
    c.avatar_url,
    c.announcement,
    dp.display_name,
    dp.avatar_url,
    last_message.body,
    last_message.sender_id,
    last_message.recalled_at,
    last_message.type,
    c.last_message_at,
    c.updated_at,
    cm.pinned_at,
    cm.muted_until,
    cm.manual_unread_at,
    mc.member_count,
    lmm.mentioned_user_ids
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and forwarded_from is null
    and public.is_current_user_conversation_member(conversation_id)
  );

create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  source_sender_name text;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null;

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'sender_name', source_sender_name,
      'type', source_message.type,
      'body', source_message.body,
      'source_attachment_bucket', source_message.attachment->>'bucket',
      'source_attachment_path', source_message.attachment->>'path'
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

drop policy if exists chat_images_select_member on storage.objects;

create policy chat_images_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-images'
    and (
      public.is_current_user_conversation_member(
        ((storage.foldername(name))[1])::uuid
      )
      or exists (
        select 1
        from public.messages m
        where m.forwarded_from->>'source_attachment_path' = name
          and m.forwarded_from->>'source_attachment_bucket' = bucket_id
          and m.recalled_at is null
          and public.is_current_user_conversation_member(m.conversation_id)
      )
    )
  );

drop policy if exists voice_messages_select_member on storage.objects;

create policy voice_messages_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'voice-messages'
    and (
      public.is_current_user_conversation_member(
        split_part(name, '/', 1)::uuid
      )
      or exists (
        select 1
        from public.messages m
        where m.forwarded_from->>'source_attachment_path' = name
          and m.forwarded_from->>'source_attachment_bucket' = bucket_id
          and m.recalled_at is null
          and public.is_current_user_conversation_member(m.conversation_id)
      )
    )
  );
