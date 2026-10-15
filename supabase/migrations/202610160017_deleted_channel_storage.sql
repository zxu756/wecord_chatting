-- Files of deleted channels and circles leave Storage too.
--
-- Deleting a channel (or a circle, which only happens with its owner's
-- account) dropped its messages but left their chat images, voice clips
-- and files in Storage, and a circle's emoji and post images as well.
-- Storage objects cannot be deleted from SQL, so, as recall_message and
-- ban_circle_member do:
--
-- * delete_circle_channel now returns (bucket_id, object_path) for the
--   chat-images, voice-messages and chat-files objects of the channel's
--   messages and of its threads' messages that no remaining message uses
--   (a forwarded copy elsewhere keeps its file). They are remembered in
--   recalled_message_media as deleted by the caller, so the existing
--   message_media_delete_recalled policy lets the client remove them.
-- * prepare_account_deletion returns the same for the circles it deletes,
--   plus everything in those circles' circle-emojis and chat-media
--   folders (emoji, stickers and post images). The delete-account Edge
--   Function removes them with the service role.

-- Remembers the media of the messages in [target_conversation_ids] as
-- deleted by [deleter_id] and returns them, before the conversations go.
create or replace function public.remember_conversation_media(
  target_conversation_ids uuid[],
  deleter_id uuid
)
returns table (media_bucket text, media_path text)
language sql
volatile
security definer
set search_path = public
as $$
  insert into public.recalled_message_media as r (
    bucket_id,
    object_path,
    message_id,
    deleted_by
  )
  select distinct on (media.bucket, media.path)
    media.bucket,
    media.path,
    media.message_id,
    deleter_id
  from (
    select
      m.attachment->>'bucket' as bucket,
      m.attachment->>'path' as path,
      m.id as message_id,
      m.created_at
    from public.messages m
    where m.conversation_id = any (target_conversation_ids)
      and m.attachment->>'path' is not null
      and m.attachment->>'bucket' in ('chat-images', 'voice-messages', 'chat-files')
  ) media
  order by media.bucket, media.path, media.created_at desc
  on conflict on constraint recalled_message_media_pkey do update
  set
    message_id = excluded.message_id,
    deleted_by = excluded.deleted_by,
    created_at = now()
  returning r.bucket_id, r.object_path;
$$;

revoke execute on function public.remember_conversation_media(uuid[], uuid) from public;
revoke execute on function public.remember_conversation_media(uuid[], uuid) from anon;
revoke execute on function public.remember_conversation_media(uuid[], uuid) from authenticated;

-- Same as 202610130019_channel_management, but it returns the files of the
-- channel's messages that nothing else uses, for the client to remove.
drop function if exists public.delete_circle_channel(uuid);

create or replace function public.delete_circle_channel(target_channel_id uuid)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  media_buckets text[];
  media_paths text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_circle_permission(
      channel.circle_id,
      'manage_channels'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
  then
    raise exception 'Only members who can manage channels can delete channels'
      using errcode = '42501';
  end if;

  -- Serialize with channel creation and reordering in the circle.
  perform 1 from public.circles c where c.id = channel.circle_id for no key update;

  perform public.write_circle_audit(
    channel.circle_id,
    'channel_delete',
    'channel',
    channel.id,
    channel.name,
    jsonb_build_object(
      'name', channel.name,
      'kind', channel.kind,
      'topic', channel.topic,
      'category_id', channel.category_id,
      'category_name', (
        select ccc.name
        from public.circle_channel_categories ccc
        where ccc.id = channel.category_id
      ),
      'thread_count', (
        select count(*)
        from public.conversation_threads ct
        where ct.parent_conversation_id = channel.conversation_id
      )
    )
  );

  select
    coalesce(array_agg(media.media_bucket), '{}'),
    coalesce(array_agg(media.media_path), '{}')
  into media_buckets, media_paths
  from public.remember_conversation_media(
    array(
      select channel.conversation_id
      union all
      select ct.conversation_id
      from public.conversation_threads ct
      where ct.parent_conversation_id = channel.conversation_id
    ),
    current_user_id
  ) media;

  -- Cascades to the channel row, messages, members, overwrites and
  -- threads.
  delete from public.conversations c where c.id = channel.conversation_id;

  return query
  select u.media_bucket, u.media_path
  from unnest(media_buckets, media_paths) as u(media_bucket, media_path)
  where not exists (
    select 1
    from public.messages m
    where m.attachment->>'path' = u.media_path
      and m.attachment->>'bucket' = u.media_bucket
  );
end;
$$;

revoke execute on function public.delete_circle_channel(uuid) from public;
revoke execute on function public.delete_circle_channel(uuid) from anon;
grant execute on function public.delete_circle_channel(uuid) to authenticated;

-- Same as 202610140005_delete_account, but it returns the Storage objects
-- of the circles it deletes (their messages' files nothing else uses, and
-- their emoji and post images) for the delete-account function to remove.
drop function if exists public.prepare_account_deletion();

create or replace function public.prepare_account_deletion()
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  membership record;
  media_buckets text[];
  media_paths text[];
  circle_objects_buckets text[];
  circle_objects_paths text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circles c
    join public.circle_members other
      on other.circle_id = c.id
      and other.user_id <> current_user_id
    where c.owner_id = current_user_id
  ) then
    raise exception 'Transfer the circles you own to another member first'
      using errcode = '55000';
  end if;

  -- Emoji, stickers and post images live under <circle_id>/.
  select
    coalesce(array_agg(o.bucket_id), '{}'),
    coalesce(array_agg(o.name), '{}')
  into circle_objects_buckets, circle_objects_paths
  from storage.objects o
  join public.circles c
    on c.owner_id = current_user_id
    and o.name like c.id::text || '/%'
  where o.bucket_id in ('circle-emojis', 'chat-media');

  select
    coalesce(array_agg(media.media_bucket), '{}'),
    coalesce(array_agg(media.media_path), '{}')
  into media_buckets, media_paths
  from public.remember_conversation_media(
    array(
      select ct.conversation_id
      from public.conversation_threads ct
      join public.circle_channels cc
        on cc.conversation_id = ct.parent_conversation_id
      join public.circles c on c.id = cc.circle_id
      where c.owner_id = current_user_id
      union all
      select cc.conversation_id
      from public.circle_channels cc
      join public.circles c on c.id = cc.circle_id
      where c.owner_id = current_user_id
    ),
    current_user_id
  ) media;

  -- Circles nobody else is in go with the account, channels included.
  delete from public.conversations conv
  where conv.id in (
    select ct.conversation_id
    from public.conversation_threads ct
    join public.circle_channels cc
      on cc.conversation_id = ct.parent_conversation_id
    join public.circles c on c.id = cc.circle_id
    where c.owner_id = current_user_id
    union all
    select cc.conversation_id
    from public.circle_channels cc
    join public.circles c on c.id = cc.circle_id
    where c.owner_id = current_user_id
  );

  delete from public.circles c where c.owner_id = current_user_id;

  -- Groups they solely own pass to the member who joined first.
  update public.conversation_members cm
  set role = 'owner'
  from (
    select distinct on (other.conversation_id)
      other.conversation_id,
      other.user_id
    from public.conversation_members mine
    join public.conversations c
      on c.id = mine.conversation_id
      and c.type = 'group'
    join public.conversation_members other
      on other.conversation_id = mine.conversation_id
      and other.user_id <> current_user_id
    where mine.user_id = current_user_id
      and mine.role = 'owner'
      and not exists (
        select 1
        from public.conversation_members co_owner
        where co_owner.conversation_id = mine.conversation_id
          and co_owner.role = 'owner'
          and co_owner.user_id <> current_user_id
      )
    order by other.conversation_id, other.joined_at, other.user_id
  ) heir
  where cm.conversation_id = heir.conversation_id
    and cm.user_id = heir.user_id;

  delete from public.voice_states vs where vs.user_id = current_user_id;

  for membership in
    select cm.circle_id
    from public.circle_members cm
    where cm.user_id = current_user_id
  loop
    perform public.remove_circle_member_rows(
      membership.circle_id,
      current_user_id
    );
  end loop;

  delete from public.conversation_members cm
  using public.conversations c
  where c.id = cm.conversation_id
    and c.type = 'group'
    and cm.user_id = current_user_id;

  delete from public.friendships f
  where current_user_id in (f.user_low_id, f.user_high_id);

  delete from public.friend_requests fr
  where current_user_id in (fr.requester_id, fr.receiver_id);

  delete from public.blocks b
  where current_user_id in (b.blocker_id, b.blocked_id);

  delete from public.contact_aliases ca
  where current_user_id in (ca.owner_id, ca.friend_id);

  delete from public.user_privacy_settings ups
  where ups.user_id = current_user_id;

  delete from public.circle_post_likes l where l.user_id = current_user_id;

  update public.profiles p
  set
    username = 'deleted_' || substr(replace(p.id::text, '-', ''), 1, 15),
    display_name = 'Deleted User',
    avatar_url = null,
    bio = '',
    status_emoji = null,
    status_text = null,
    status_expires_at = null,
    deleted_at = coalesce(p.deleted_at, now()),
    updated_at = now()
  where p.id = current_user_id;

  return query
  select u.media_bucket, u.media_path
  from unnest(media_buckets, media_paths) as u(media_bucket, media_path)
  where not exists (
    select 1
    from public.messages m
    where m.attachment->>'path' = u.media_path
      and m.attachment->>'bucket' = u.media_bucket
  )
  union all
  select u.object_bucket, u.object_name
  from unnest(circle_objects_buckets, circle_objects_paths)
    as u(object_bucket, object_name);
end;
$$;

revoke execute on function public.prepare_account_deletion() from public;
revoke execute on function public.prepare_account_deletion() from anon;
grant execute on function public.prepare_account_deletion() to authenticated;
