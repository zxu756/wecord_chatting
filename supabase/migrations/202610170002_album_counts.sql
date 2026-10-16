-- An album counts as one message wherever a recipient sees a count.
--
-- Each picture, video or file of an album is a message of its own (see
-- 202610170001_media_albums), so counting rows made a 6 photo album read
-- as "6 new messages". The counts below are of distinct
-- coalesce(attachment_group_id, id): the messages of one album that fall
-- in the counted range add up to one.
--
-- count(*) - count(g) + count(distinct g) is that number without sorting
-- every id: it takes the rows, takes off those that belong to an album and
-- adds one per album (count(distinct g) ignores the nulls of single
-- messages). Only the album ids are sorted.
--
-- Redefined, with nothing else changed:
-- * list_circle_summaries (202610130024_channel_webhooks): the unread and
--   mention counts of the circle rail.
-- * thread_payload (202610130011_message_threads): the reply and unread
--   counts of a thread.
-- * forum_post_payload (202610130020_forum_channels): the reply and
--   unread counts of a forum post.
-- * list_inbox (202610160003_role_and_here_mentions): an album that
--   mentions the reader or replies to them is one inbox row (its first
--   message that does).
-- list_conversation_summaries follows in 202610170003.

-- Unread messages are those of a conversation after a point in time that
-- the reader did not send. The sender and album id ride along in the
-- index, so counting them does not visit the table for every row.
create index if not exists messages_conversation_unread_idx
  on public.messages (conversation_id, created_at desc)
  include (sender_id, attachment_group_id, webhook_name);

-- Same as 202610130024_channel_webhooks, but an album is one unread
-- message and one mention.
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

grant execute on function public.list_circle_summaries() to authenticated;

-- Same as 202610130011_message_threads, but an album is one reply and one
-- unread message.
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

revoke execute on function public.thread_payload(public.conversation_threads) from public;
revoke execute on function public.thread_payload(public.conversation_threads) from anon;
revoke execute on function public.thread_payload(public.conversation_threads) from authenticated;

-- Same as 202610130020_forum_channels, but an album is one reply and one
-- unread message.
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
        and m.id is distinct from opening.id
    ),
    'thumbnail', (
      select m.attachment
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.recalled_at is null
        and m.type in ('text', 'image')
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
    order by m.created_at, m.id
    limit 1
  ) opening on true;
$$;

revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from public;
revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from anon;
revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from authenticated;

-- Same as 202610160003_role_and_here_mentions, but the messages of one
-- album are listed once: the first of them that mentions the reader or
-- replies to them.
create or replace function public.list_inbox(p_limit integer default 50)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  body text,
  type text,
  created_at timestamptz,
  reason text,
  is_unread boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  with since as (
    select now() - interval '30 days' as at
  ),
  mentioned as (
    select
      mm.message_id,
      case
        when bool_or(mm.kind = 'user') then 'mention'
        when bool_or(mm.kind = 'role') then 'mention_role'
        when bool_or(mm.kind = 'here') then 'mention_here'
        else 'mention_all'
      end as reason
    from public.message_mentions mm, since
    where mm.user_id = auth.uid()
      and mm.created_at > since.at
    group by mm.message_id
  ),
  replied as (
    select reply.id as message_id, 'reply'::text as reason
    from public.messages parent
    join public.messages reply on reply.reply_to_message_id = parent.id
    cross join since
    where parent.sender_id = auth.uid()
      and reply.created_at > since.at
  ),
  -- A reply that also mentions the user is listed once, as a mention.
  hits as (
    select distinct on (message_id) message_id, reason
    from (
      select message_id, reason, 0 as rank from mentioned
      union all
      select message_id, reason, 1 as rank from replied
    ) candidates
    order by message_id, rank
  ),
  -- One row per message, or per album.
  inbox_rows as (
    select distinct on (m.sender_id, coalesce(m.attachment_group_id, m.id))
      m.id as message_id,
      m.conversation_id,
      m.sender_id,
      p.display_name as sender_display_name,
      p.avatar_url as sender_avatar_url,
      m.webhook_name,
      m.body,
      m.type,
      m.created_at,
      hits.reason,
      m.created_at > coalesce(last_read.created_at, '-infinity'::timestamptz)
        as is_unread
    from hits
    join public.messages m on m.id = hits.message_id
    join public.profiles p on p.id = m.sender_id
    join public.conversation_members cm
      on cm.conversation_id = m.conversation_id
     and cm.user_id = auth.uid()
    left join public.messages last_read on last_read.id = cm.last_read_message_id
    where m.sender_id <> auth.uid()
      and m.recalled_at is null
      and m.type <> 'system'
    order by
      m.sender_id,
      coalesce(m.attachment_group_id, m.id),
      m.created_at,
      m.id
  )
  select
    r.message_id,
    r.conversation_id,
    r.sender_id,
    r.sender_display_name,
    r.sender_avatar_url,
    r.webhook_name,
    r.body,
    r.type,
    r.created_at,
    r.reason,
    r.is_unread
  from inbox_rows r
  order by r.created_at desc, r.message_id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke execute on function public.list_inbox(integer) from public;
revoke execute on function public.list_inbox(integer) from anon;
grant execute on function public.list_inbox(integer) to authenticated;
