-- Soundboard clips leave Storage with their circle.
--
-- Circles are only deleted with their owner's account. prepare_account_deletion
-- returned the circle's circle-emojis and chat-media objects for the
-- delete-account function to remove; it now returns the circle's
-- circle-sounds clips too (<circle_id>/<uuid>.<mp3|ogg|wav>). The function
-- removes whatever buckets it is given, so it needs no change. Channels
-- own no clips, so delete_circle_channel stays as it is.

-- Same as 202610160017_deleted_channel_storage, plus the circle-sounds
-- bucket.
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

  -- Emoji, stickers, post images and soundboard clips live under
  -- <circle_id>/.
  select
    coalesce(array_agg(o.bucket_id), '{}'),
    coalesce(array_agg(o.name), '{}')
  into circle_objects_buckets, circle_objects_paths
  from storage.objects o
  join public.circles c
    on c.owner_id = current_user_id
    and o.name like c.id::text || '/%'
  where o.bucket_id in ('circle-emojis', 'chat-media', 'circle-sounds');

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
