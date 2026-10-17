-- AI guard, part 2 of 2: a message waiting for review (messages.review_state
-- 'checking', 'held' or 'removed', see 202610170090_ai_guard.sql) is seen
-- only by its author and by members who moderate its channel.
--
-- * The select policy hides it, which also covers realtime, search by the
--   client, link previews and every function that reads as the caller.
-- * The functions below read as their owner, so each leaves it out the way
--   it leaves out recalled messages: unread and mention counts, the
--   conversation's and circle's latest activity, pins, forum and thread
--   counts, search entries, bots, forwarding and above all pushes. None of
--   them counts, shows or pushes it until it is released; releasing
--   (finish_message_review / decide_message_review) then does what the
--   insert triggers skipped: it moves the conversation's and thread's
--   latest message, writes the search entry and queues the push.
-- * Every redefinition is the latest definition of the function with only
--   the review condition added; the file it came from is named above it.

-- The select policy: 202610170020_disappearing_messages plus the review
-- condition (evaluated for hidden rows only).
drop policy if exists messages_select_member on public.messages;
create policy messages_select_member
  on public.messages for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
    and (expires_at is null or expires_at > now())
    and (
      review_state is null
      or sender_id = auth.uid()
      or public.can_current_user_moderate_messages(conversation_id)
    )
  );

-- A message waiting for review does not move the conversation's latest
-- message (202605180001_private_chat) or its thread's activity
-- (202610130011_message_threads): releasing it does.
create or replace function public.touch_conversation_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.review_state is not null then
    return new;
  end if;

  update public.conversations
  set
    last_message_id = new.id,
    last_message_at = new.created_at,
    updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$$;

create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.review_state is not null then
    return new;
  end if;

  update public.conversation_threads ct
  set
    last_message_at = new.created_at,
    archived_at = case when new.type = 'system' then ct.archived_at else null end
  where ct.conversation_id = new.conversation_id;

  return new;
end;
$$;

-- The search entry (202610160043_message_search_indexes): none while the
-- message waits for review, written when it is released, with its new time.
create or replace function public.sync_message_search_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recalled_at is not null
    or new.type = 'system'
    or new.review_state is not null
  then
    if tg_op = 'UPDATE' then
      delete from public.message_search_entries where message_id = new.id;
    end if;
    return null;
  end if;
  if tg_op = 'UPDATE'
    and new.body is not distinct from old.body
    and new.attachment is not distinct from old.attachment
    and new.type is not distinct from old.type
    and new.created_at is not distinct from old.created_at
    and old.recalled_at is null
    and old.review_state is null
  then
    return null;
  end if;
  insert into public.message_search_entries as e (
    message_id, conversation_id, sender_id, created_at, document, vector, kinds
  )
  values (
    new.id,
    new.conversation_id,
    new.sender_id,
    new.created_at,
    public.message_search_document(new.type, new.body, new.attachment),
    public.message_search_vector(new.type, new.body, new.attachment),
    public.message_search_kinds(new.type, new.body, new.attachment)
  )
  on conflict (message_id) do update
  set document = excluded.document,
    vector = excluded.vector,
    kinds = excluded.kinds,
    created_at = excluded.created_at;
  return null;
end;
$$;

drop trigger if exists messages_sync_search_entry on public.messages;
create trigger messages_sync_search_entry
  after insert or update of type, body, attachment, recalled_at, review_state, created_at
  on public.messages
  for each row execute function public.sync_message_search_entry();

-- Conversation list
-- Same as 202610170003_album_summaries.sql, but messages waiting for review are not unread.
create or replace function public.list_conversation_summaries()
returns table (
  id uuid,
  type text,
  title text,
  avatar_url text,
  announcement text,
  announcement_updated_at timestamptz,
  announcement_updated_by uuid,
  last_message_body text,
  last_message_sender_id uuid,
  last_message_at timestamptz,
  last_message_type text,
  last_message_webhook_name text,
  last_message_attachment_kind text,
  last_message_album jsonb,
  unread_count bigint,
  pinned_at timestamptz,
  muted_until timestamptz,
  is_muted boolean,
  is_marked_unread boolean,
  member_count bigint,
  mentioned_user_ids uuid[],
  circle_id uuid,
  circle_notification_level text,
  circle_muted_until timestamptz,
  direct_user_id uuid,
  direct_custom_status jsonb,
  parent_conversation_id uuid,
  parent_title text,
  thread_id uuid,
  thread_archived_at timestamptz,
  thread_last_activity_at timestamptz,
  can_send_messages boolean,
  slowmode_seconds integer
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
      and public.user_has_conversation_channel_permission(
        cm.conversation_id,
        auth.uid(),
        'view_channel'
      )
  ),
  read_markers as (
    select cm.conversation_id, rm.created_at as last_read_at
    from current_memberships cm
    left join public.messages rm on rm.id = cm.last_read_message_id
  ),
  -- Messages from others (and webhooks) after the read marker, an album
  -- counted once. Worked out per conversation on its own, so the summary
  -- query below needs no GROUP BY over all its columns.
  unread_counts as (
    select
      rm.conversation_id,
      count(unread_messages.id)
        - count(unread_messages.attachment_group_id)
        + count(distinct unread_messages.attachment_group_id) as unread_count
    from read_markers rm
    join public.messages unread_messages
      on unread_messages.conversation_id = rm.conversation_id
      and unread_messages.review_state is null
      and (
        unread_messages.sender_id <> auth.uid()
        or unread_messages.webhook_name is not null
      )
      and (
        rm.last_read_at is null
        or unread_messages.created_at > rm.last_read_at
      )
    group by rm.conversation_id
  ),
  direct_profiles as (
    select
      cm.conversation_id,
      p.id as user_id,
      coalesce(ca.alias, p.display_name) as display_name,
      p.avatar_url,
      case
        when exists (
          select 1
          from public.blocks b
          where b.blocker_id = p.id
            and b.blocked_id = auth.uid()
        ) then null
        else public.custom_status(p)
      end as custom_status
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
    c.announcement_updated_at,
    c.announcement_updated_by,
    case
      when last_message.recalled_at is not null then 'Message deleted'
      when last_message.type = 'image' then '[Image]'
      else last_message.body
    end as last_message_body,
    last_message.sender_id as last_message_sender_id,
    c.last_message_at,
    last_message.type as last_message_type,
    last_message.webhook_name as last_message_webhook_name,
    case
      when last_message.recalled_at is not null then null
      when last_message.type <> 'file' then null
      when last_message.attachment->>'kind' = 'video'
        or last_message.attachment->>'mime_type' like 'video/%' then 'video'
      else 'file'
    end as last_message_attachment_kind,
    case
      when album.total >= 2 then album.counts
      else null
    end as last_message_album,
    greatest(
      coalesce(uc.unread_count, 0),
      case when cm.manual_unread_at is null then 0 else 1 end::bigint
    ) as unread_count,
    cm.pinned_at,
    cm.muted_until,
    cm.muted_until is not null and cm.muted_until > now() as is_muted,
    cm.manual_unread_at is not null as is_marked_unread,
    coalesce(mc.member_count, 0) as member_count,
    coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids,
    cc.circle_id,
    case
      when cc.circle_id is null then null
      else coalesce(cns.level, 'all')
    end as circle_notification_level,
    cns.muted_until as circle_muted_until,
    dp.user_id as direct_user_id,
    dp.custom_status as direct_custom_status,
    ct.parent_conversation_id,
    parent_conversation.title as parent_title,
    ct.id as thread_id,
    ct.archived_at as thread_archived_at,
    coalesce(ct.last_message_at, ct.created_at) as thread_last_activity_at,
    cc.id is null
      or public.circle_channel_has_permission(
        cc.id,
        auth.uid(),
        'send_messages'
      ) as can_send_messages,
    case
      when ct.id is null
        and cc.slowmode_seconds > 0
        and not public.circle_channel_has_permission(
          cc.id,
          auth.uid(),
          'manage_messages'
        )
        then cc.slowmode_seconds
      else 0
    end as slowmode_seconds
  from public.conversations c
  join current_memberships cm on cm.conversation_id = c.id
  left join read_markers rm on rm.conversation_id = c.id
  left join direct_profiles dp on dp.conversation_id = c.id and c.type = 'direct'
  left join member_counts mc on mc.conversation_id = c.id
  left join public.messages last_message on last_message.id = c.last_message_id
  left join last_message_mentions lmm on lmm.message_id = last_message.id
  -- The rest of the latest message's album, if it is in one.
  left join lateral (
    select
      count(*) as total,
      jsonb_build_object(
        'images', count(*) filter (where album_message.type = 'image'),
        'videos', count(*) filter (
          where album_message.type = 'file'
            and coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        ),
        'files', count(*) filter (
          where album_message.type = 'file'
            and not coalesce(
              album_message.attachment->>'kind' = 'video'
                or album_message.attachment->>'mime_type' like 'video/%',
              false
            )
        )
      ) as counts
    from public.messages album_message
    where album_message.conversation_id = c.id
      and album_message.sender_id = last_message.sender_id
      and album_message.attachment_group_id = last_message.attachment_group_id
      and album_message.recalled_at is null
  ) album
    on last_message.attachment_group_id is not null
    and last_message.recalled_at is null
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.conversations parent_conversation
    on parent_conversation.id = ct.parent_conversation_id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  left join public.circle_notification_settings cns
    on cns.circle_id = cc.circle_id
    and cns.user_id = auth.uid()
  left join unread_counts uc on uc.conversation_id = c.id
  where cm.hidden_at is null
    or c.last_message_at > cm.hidden_at
  order by
    cm.pinned_at desc nulls last,
    c.last_message_at desc nulls last,
    c.updated_at desc;
$$;

-- Circle rail
-- Same as 202610170002_album_counts.sql, but messages waiting for review are neither unread nor
-- mentions.
create or replace function public.list_circle_summaries()
returns table (
  id uuid,
  name text,
  avatar_url text,
  member_count bigint,
  channel_count bigint,
  latest_activity_at timestamptz,
  current_user_role text,
  unread_count bigint,
  mention_count bigint,
  is_muted boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with visible_channels as (
    select cc.id, cc.circle_id, cc.conversation_id
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    where current_member.user_id = auth.uid()
      and public.circle_channel_has_permission(cc.id, auth.uid(), 'view_channel')
  ),
  circle_conversations as (
    select vc.circle_id, vc.conversation_id
    from visible_channels vc
    union all
    select vc.circle_id, ct.conversation_id
    from visible_channels vc
    join public.conversation_threads ct
      on ct.parent_conversation_id = vc.conversation_id
  ),
  channel_reads as (
    select
      cc.circle_id,
      cc.conversation_id,
      conv_member.manual_unread_at,
      read_message.created_at as last_read_at
    from circle_conversations cc
    join public.conversation_members conv_member
      on conv_member.conversation_id = cc.conversation_id
      and conv_member.user_id = auth.uid()
    left join public.messages read_message
      on read_message.id = conv_member.last_read_message_id
  ),
  channel_counts as (
    select
      cr.circle_id,
      greatest(
        (
          select
            count(*)
              - count(unread_message.attachment_group_id)
              + count(distinct unread_message.attachment_group_id)
          from public.messages unread_message
          where unread_message.conversation_id = cr.conversation_id
            and unread_message.review_state is null
            and (
              unread_message.sender_id <> auth.uid()
              or unread_message.webhook_name is not null
            )
            and (
              cr.last_read_at is null
              or unread_message.created_at > cr.last_read_at
            )
        ),
        case when cr.manual_unread_at is null then 0 else 1 end::bigint
      ) as unread_count,
      (
        select count(distinct coalesce(
          mentioned_message.attachment_group_id,
          mentioned_message.id
        ))
        from public.message_mentions mm
        join public.messages mentioned_message
          on mentioned_message.id = mm.message_id
        where mm.conversation_id = cr.conversation_id
          and mm.user_id = auth.uid()
          and mentioned_message.sender_id <> auth.uid()
          and mentioned_message.type <> 'system'
          and mentioned_message.review_state is null
          and (
            cr.last_read_at is null
            or mentioned_message.created_at > cr.last_read_at
          )
      ) as mention_count
    from channel_reads cr
  ),
  circle_counts as (
    select
      channel_count.circle_id,
      sum(channel_count.unread_count)::bigint as unread_count,
      sum(channel_count.mention_count)::bigint as mention_count
    from channel_counts channel_count
    group by channel_count.circle_id
  )
  select
    c.id,
    c.name,
    c.avatar_url,
    count(distinct all_members.user_id) as member_count,
    count(distinct cc.id) as channel_count,
    greatest(
      c.updated_at,
      coalesce(max(cp.created_at), c.updated_at),
      coalesce(max(ch_conversation.last_message_at), c.updated_at)
    ) as latest_activity_at,
    current_member.role as current_user_role,
    coalesce(counts.unread_count, 0) as unread_count,
    coalesce(counts.mention_count, 0) as mention_count,
    coalesce(
      cns.level = 'none'
        or (cns.muted_until is not null and cns.muted_until > now()),
      false
    ) as is_muted
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  left join public.circle_members all_members on all_members.circle_id = c.id
  left join visible_channels cc on cc.circle_id = c.id
  left join public.conversations ch_conversation
    on ch_conversation.id = cc.conversation_id
  left join public.circle_posts cp on cp.circle_id = c.id
  left join circle_counts counts on counts.circle_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = c.id
    and cns.user_id = auth.uid()
  group by
    c.id,
    c.name,
    c.avatar_url,
    c.updated_at,
    current_member.role,
    counts.unread_count,
    counts.mention_count,
    cns.level,
    cns.muted_until
  order by latest_activity_at desc, c.created_at desc;
$$;

-- Thread counts
-- Same as 202610170002_album_counts.sql, but messages waiting for review are not replies or unread.
create or replace function public.thread_payload(thread_row public.conversation_threads)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', thread_row.id,
    'conversation_id', thread_row.conversation_id,
    'parent_conversation_id', thread_row.parent_conversation_id,
    'root_message_id', thread_row.root_message_id,
    'title', thread_row.title,
    'created_by', thread_row.created_by,
    'created_at', thread_row.created_at,
    'archived_at', thread_row.archived_at,
    'last_message_at', thread_row.last_message_at,
    'reply_count', (
      select
        count(*)
          - count(m.attachment_group_id)
          + count(distinct m.attachment_group_id)
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.type <> 'system'
        and m.recalled_at is null
        and m.review_state is null
    ),
    'unread_count', (
      select
        count(*)
          - count(m.attachment_group_id)
          + count(distinct m.attachment_group_id)
      from public.conversation_members cm
      left join public.messages read_message
        on read_message.id = cm.last_read_message_id
      join public.messages m
        on m.conversation_id = cm.conversation_id
        and m.sender_id <> auth.uid()
        and m.review_state is null
        and (
          read_message.created_at is null
          or m.created_at > read_message.created_at
        )
      where cm.conversation_id = thread_row.conversation_id
        and cm.user_id = auth.uid()
    ),
    'can_manage', public.can_current_user_manage_thread(thread_row.id)
  );
$$;

-- Forum post counts
-- Same as 202610170002_album_counts.sql, but messages waiting for review are not replies or unread,
-- and only the author and moderators see one as the opening message.
create or replace function public.forum_post_payload(
  thread_row public.conversation_threads,
  forum_channel public.circle_channels
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', thread_row.id,
    'conversation_id', thread_row.conversation_id,
    'channel_id', forum_channel.id,
    'title', thread_row.title,
    'created_by', thread_row.created_by,
    'created_at', thread_row.created_at,
    'last_activity_at', coalesce(thread_row.last_message_at, thread_row.created_at),
    'archived_at', thread_row.archived_at,
    'is_pinned', thread_row.is_pinned,
    'author', case
      when author.id is null then null
      else jsonb_build_object(
        'id', author.id,
        'username', author.username,
        'display_name', author.display_name,
        'avatar_url', author.avatar_url,
        'bio', author.bio,
        'created_at', author.created_at,
        'updated_at', author.updated_at,
        'nickname', author_member.nickname,
        'role_color', (
          select r.color
          from public.circle_member_roles mr
          join public.circle_roles r on r.id = mr.role_id
          where mr.circle_id = forum_channel.circle_id
            and mr.user_id = author.id
            and r.color is not null
          order by r.position desc
          limit 1
        )
      )
    end,
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ft.id,
          'channel_id', ft.channel_id,
          'name', ft.name,
          'emoji', ft.emoji,
          'position', ft.position
        )
        order by ft.position, ft.created_at
      )
      from public.thread_tags tt
      join public.forum_tags ft on ft.id = tt.tag_id
      where tt.thread_id = thread_row.id
    ), '[]'::jsonb),
    'opening_message', case
      when opening.id is null then null
      else jsonb_build_object(
        'id', opening.id,
        'type', opening.type,
        'body', case when opening.recalled_at is null then opening.body else '' end,
        'recalled', opening.recalled_at is not null
      )
    end,
    'reply_count', (
      select
        count(*)
          - count(m.attachment_group_id)
          + count(distinct m.attachment_group_id)
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.type <> 'system'
        and m.recalled_at is null
        and m.review_state is null
        and m.id is distinct from opening.id
    ),
    'thumbnail', (
      select m.attachment
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.recalled_at is null
        and m.type in ('text', 'image')
        and m.review_state is null
        and m.attachment ->> 'kind' = 'image'
      order by m.created_at, m.id
      limit 1
    ),
    'unread_count', (
      select
        count(*)
          - count(m.attachment_group_id)
          + count(distinct m.attachment_group_id)
      from public.conversation_members cm
      left join public.messages read_message
        on read_message.id = cm.last_read_message_id
      join public.messages m
        on m.conversation_id = cm.conversation_id
        and m.sender_id <> auth.uid()
        and m.review_state is null
        and m.type <> 'system'
        and (
          read_message.created_at is null
          or m.created_at > read_message.created_at
        )
      where cm.conversation_id = thread_row.conversation_id
        and cm.user_id = auth.uid()
    ),
    'can_manage', public.can_current_user_manage_thread(thread_row.id)
  )
  from (select 1) as single_row
  left join public.profiles author on author.id = thread_row.created_by
  left join public.circle_members author_member
    on author_member.circle_id = forum_channel.circle_id
    and author_member.user_id = thread_row.created_by
  left join lateral (
    select m.id, m.type, m.body, m.recalled_at
    from public.messages m
    where m.conversation_id = thread_row.conversation_id
      and m.type <> 'system'
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    order by m.created_at, m.id
    limit 1
  ) opening on true;
$$;

-- Search context
-- Same as 202610160044_search_messages_rpc.sql, but messages waiting for review stay out of the context.
create or replace function public.search_message_context(
  target_message_id uuid,
  before_count integer,
  after_count integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  target public.messages;
  before_rows jsonb;
  after_rows jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  select m.* into target
  from public.messages m
  where m.id = target_message_id
    and m.conversation_id in (
      select public.current_user_readable_conversation_ids()
    )
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id);
  if target.id is null then
    return jsonb_build_object('before', '[]'::jsonb, 'after', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(public.search_message_json(b, 0, caller)
    order by b.created_at, b.id), '[]'::jsonb)
  into before_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) < (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    order by m.created_at desc, m.id desc
    limit least(greatest(coalesce(before_count, 1), 0), 10)
  ) b;

  select coalesce(jsonb_agg(public.search_message_json(a, 0, caller)
    order by a.created_at, a.id), '[]'::jsonb)
  into after_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) > (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
      and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    order by m.created_at, m.id
    limit least(greatest(coalesce(after_count, 1), 0), 10)
  ) a;

  return jsonb_build_object('before', before_rows, 'after', after_rows);
end;
$$;

-- Pinned messages
-- Same as 202610130002_pinned_messages.sql, but a message waiting for review is not listed for those who
-- cannot see it.
create or replace function public.list_pinned_messages(
  target_conversation_id uuid
)
returns table (
  message jsonb,
  sender jsonb,
  pinned_by uuid,
  pinned_by_name text,
  pinned_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  return query
  select
    to_jsonb(m) || jsonb_build_object('is_pinned', true) as message,
    jsonb_build_object(
      'id', sender_profile.id,
      'username', sender_profile.username,
      'display_name', sender_profile.display_name,
      'alias', sender_alias.alias,
      'avatar_url', sender_profile.avatar_url,
      'bio', sender_profile.bio,
      'created_at', sender_profile.created_at,
      'updated_at', sender_profile.updated_at
    ) as sender,
    pm.pinned_by,
    coalesce(pinner_alias.alias, pinner.display_name) as pinned_by_name,
    pm.pinned_at
  from public.pinned_messages pm
  join public.messages m on m.id = pm.message_id
  join public.profiles sender_profile on sender_profile.id = m.sender_id
  left join public.contact_aliases sender_alias
    on sender_alias.owner_id = auth.uid()
    and sender_alias.friend_id = sender_profile.id
  left join public.profiles pinner on pinner.id = pm.pinned_by
  left join public.contact_aliases pinner_alias
    on pinner_alias.owner_id = auth.uid()
    and pinner_alias.friend_id = pinner.id
  where pm.conversation_id = target_conversation_id
    and m.recalled_at is null
    and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
  order by pm.pinned_at desc, m.id;
end;
$$;

-- Bot API
-- Same as 202610160030_bot_api.sql, but bots do not read messages waiting for review.
create or replace function public.bot_api_list_messages(
  bot_token text,
  target_channel_id uuid,
  max_count integer default 50,
  before_time timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  channel public.circle_channels%rowtype := public.bot_visible_channel(bot, target_channel_id);
begin
  return coalesce((
    select jsonb_agg(item order by created_at desc, id desc)
    from (
      select
        m.id,
        m.created_at,
        jsonb_build_object(
          'id', m.id,
          'channel_id', channel.id,
          'type', m.type,
          'content', case when m.recalled_at is null then m.body else '' end,
          'deleted', m.recalled_at is not null,
          'created_at', m.created_at,
          'edited_at', m.edited_at,
          'reply_to_message_id', m.reply_to_message_id,
          'author', case
            when m.webhook_name is not null then jsonb_build_object(
              'webhook', true,
              'name', m.webhook_name
            )
            else jsonb_build_object(
              'id', p.id,
              'username', p.username,
              'name', public.circle_member_label(bot.circle_id, p.id),
              'is_bot', p.is_bot
            )
          end,
          'interaction', m.interaction
        ) as item
      from public.messages m
      join public.profiles p on p.id = m.sender_id
      where m.conversation_id = channel.conversation_id
        and m.type <> 'system'
        and m.review_state is null
        and (before_time is null or m.created_at < before_time)
      order by m.created_at desc, m.id desc
      limit least(greatest(coalesce(max_count, 50), 1), 100)
    ) page
  ), '[]'::jsonb);
end;
$$;

-- Push
-- Same as 202610170005_push_language.sql, but a message waiting for review is not pushed (and not
-- marked as pushed).
create or replace function public.claim_push_delivery(
  target_message_id uuid,
  caller_id uuid
)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  message public.messages%rowtype;
  conv public.conversations%rowtype;
  channel public.circle_channels%rowtype;
  circle_name text;
  sender_name text;
  title_en text;
  title_zh text;
  body_en text;
  body_zh text;
  album_images integer := 0;
  album_videos integer := 0;
  album_files integer := 0;
  album_parts_en text[] := array[]::text[];
  album_parts_zh text[] := array[]::text[];
begin
  select m.*
  into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.sender_id is distinct from caller_id
    or message.recalled_at is not null
    -- Waiting for review: pushed when it is released (claim_released_message_pushes).
    or message.review_state is not null
    or message.webhook_id is not null
    or (message.type = 'system' and message.attachment->>'kind' is distinct from 'call')
  then
    return;
  end if;

  if message.attachment_group_id is not null then
    -- Two items of an album claiming at once must not both pass.
    perform pg_advisory_xact_lock(
      hashtextextended('push-album:' || message.attachment_group_id::text, 0)
    );

    if exists (
      select 1
      from public.messages sibling
      join public.push_deliveries delivery on delivery.message_id = sibling.id
      where sibling.conversation_id = message.conversation_id
        and sibling.sender_id = message.sender_id
        and sibling.attachment_group_id = message.attachment_group_id
        and sibling.id <> message.id
    ) then
      return;
    end if;

    select
      count(*) filter (where sibling.type = 'image'),
      count(*) filter (
        where sibling.type = 'file'
          and coalesce(
            sibling.attachment->>'kind' = 'video'
              or sibling.attachment->>'mime_type' like 'video/%',
            false
          )
      ),
      count(*) filter (
        where sibling.type = 'file'
          and not coalesce(
            sibling.attachment->>'kind' = 'video'
              or sibling.attachment->>'mime_type' like 'video/%',
            false
          )
      )
    into album_images, album_videos, album_files
    from public.messages sibling
    where sibling.conversation_id = message.conversation_id
      and sibling.sender_id = message.sender_id
      and sibling.attachment_group_id = message.attachment_group_id
      and sibling.recalled_at is null;
  end if;

  insert into public.push_deliveries (message_id)
  values (message.id)
  on conflict do nothing;
  if not found then
    return;
  end if;

  select c.* into conv from public.conversations c where c.id = message.conversation_id;

  select cc.*
  into channel
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(message.conversation_id);

  if channel.id is not null then
    select ci.name into circle_name from public.circles ci where ci.id = channel.circle_id;
  end if;

  select coalesce(
    nullif(btrim(public.sender_nickname(message)), ''),
    nullif(btrim(p.display_name), ''),
    p.username
  )
  into sender_name
  from public.profiles p
  where p.id = message.sender_id;

  title_en := case
    when channel.id is not null then
      coalesce(sender_name, 'Someone')
        || ' (#' || channel.name || ', ' || coalesce(circle_name, 'circle') || ')'
    when conv.type = 'group' then
      coalesce(sender_name, 'Someone')
        || ' (' || coalesce(nullif(btrim(conv.title), ''), 'group') || ')'
    else coalesce(sender_name, 'Someone')
  end;
  title_zh := case
    when channel.id is not null then
      coalesce(sender_name, '某人')
        || ' (#' || channel.name || ', ' || coalesce(circle_name, '圈子') || ')'
    when conv.type = 'group' then
      coalesce(sender_name, '某人')
        || ' (' || coalesce(nullif(btrim(conv.title), ''), '群聊') || ')'
    else coalesce(sender_name, '某人')
  end;

  if album_images + album_videos + album_files >= 2 then
    if album_images > 0 then
      album_parts_en := album_parts_en || format(
        case when album_images = 1 then '%s photo' else '%s photos' end,
        album_images
      );
      album_parts_zh := album_parts_zh || format('%s 张照片', album_images);
    end if;
    if album_videos > 0 then
      album_parts_en := album_parts_en || format(
        case when album_videos = 1 then '%s video' else '%s videos' end,
        album_videos
      );
      album_parts_zh := album_parts_zh || format('%s 个视频', album_videos);
    end if;
    if album_files > 0 then
      album_parts_en := album_parts_en || format(
        case when album_files = 1 then '%s file' else '%s files' end,
        album_files
      );
      album_parts_zh := album_parts_zh || format('%s 个文件', album_files);
    end if;
    body_en := 'sent ' || array_to_string(album_parts_en, ', ');
    body_zh := '发来 ' || array_to_string(album_parts_zh, '、');
  else
    body_en := case message.type
      when 'text' then left(regexp_replace(message.body, '\s+', ' ', 'g'), 160)
      when 'image' then '[Image]'
      when 'voice' then '[Voice message]'
      when 'file' then
        case when message.attachment->>'kind' = 'video' then '[Video]' else '[File]' end
      when 'poll' then '[Poll]'
      when 'sticker' then '[Sticker]'
      when 'system' then message.body
      else '[Message]'
    end;
    body_zh := case message.type
      when 'text' then body_en
      when 'image' then '[图片]'
      when 'voice' then '[语音消息]'
      when 'file' then
        case when message.attachment->>'kind' = 'video' then '[视频]' else '[文件]' end
      when 'poll' then '[投票]'
      when 'sticker' then '[贴纸]'
      -- Only "X started a call." notices get here.
      when 'system' then coalesce(sender_name, '某人') || ' 发起了通话'
      else '[消息]'
    end;
  end if;

  return query
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    message.conversation_id,
    channel.circle_id,
    case when s.language = 'zh' then title_zh else title_en end,
    case when s.language = 'zh' then body_zh else body_en end
  from public.conversation_members cm
  join public.push_subscriptions s on s.user_id = cm.user_id
  left join public.circle_notification_settings ns
    on ns.circle_id = channel.circle_id
    and ns.user_id = cm.user_id
  left join public.user_privacy_settings ups on ups.user_id = cm.user_id
  where cm.conversation_id = message.conversation_id
    and cm.user_id <> message.sender_id
    and (cm.muted_until is null or cm.muted_until < now())
    and coalesce(ups.presence_status, 'online') <> 'dnd'
    and not public.are_users_blocked(message.sender_id, cm.user_id)
    and public.user_has_conversation_channel_permission(
      message.conversation_id,
      cm.user_id,
      'view_channel'
    )
    and (
      channel.id is null
      or ns.user_id is null
      or (
        (ns.muted_until is null or ns.muted_until < now())
        and (
          ns.level = 'all'
          or (
            ns.level = 'mentions'
            and exists (
              select 1
              from public.message_mentions mm
              where mm.message_id = message.id
                and mm.user_id = cm.user_id
            )
          )
        )
      )
    );
end;
$$;

-- Forwarding
-- Same as 202610160035_automod_quiet_sends.sql, but a message waiting for review cannot be forwarded.
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
    and recalled_at is null
    and type <> 'system'
    and type <> 'poll'
    and type <> 'sticker'
    and review_state is null;

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

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

  perform set_config('wecord.automod_soft', 'off', true);

  return created_message_id;
end;
$$;
