-- Same as 202605190003_community_discovery_v1, plus unread and mention
-- counts summed over the circle's channels for the current user, counted the
-- way list_conversation_summaries counts them: messages from others after
-- the channel's read marker (a manually unread channel counts at least 1),
-- and mentions of the current user in those messages, ignoring system
-- notices. is_muted is true while the circle is muted or set to 'none', so
-- the client can dim it instead of highlighting the counts.
drop function if exists public.list_circle_summaries();

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
  with channel_reads as (
    select
      cc.circle_id,
      cc.conversation_id,
      conv_member.manual_unread_at,
      read_message.created_at as last_read_at
    from public.circle_members current_member
    join public.circle_channels cc on cc.circle_id = current_member.circle_id
    join public.conversation_members conv_member
      on conv_member.conversation_id = cc.conversation_id
      and conv_member.user_id = auth.uid()
    left join public.messages read_message
      on read_message.id = conv_member.last_read_message_id
    where current_member.user_id = auth.uid()
  ),
  channel_counts as (
    select
      cr.circle_id,
      greatest(
        (
          select count(*)
          from public.messages unread_message
          where unread_message.conversation_id = cr.conversation_id
            and unread_message.sender_id <> auth.uid()
            and (
              cr.last_read_at is null
              or unread_message.created_at > cr.last_read_at
            )
        ),
        case when cr.manual_unread_at is null then 0 else 1 end::bigint
      ) as unread_count,
      (
        select count(distinct mentioned_message.id)
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
  left join public.circle_channels cc on cc.circle_id = c.id
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
