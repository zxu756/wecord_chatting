-- L6 (scale): the hot queries of the chat list, the circle list, a send in a
-- big group and the legacy message search, made cheaper without changing what
-- they return. Found by tool/scale/run_scale.sh (see docs/scale-report.md): a
-- 10000-member circle, a 5000-member group and 400000 messages in the local
-- database.
--
-- What was wrong, and the fix:
--
-- * is_current_user_blocked_in_conversation joined every other member of a
--   chat (and checked blocks for each) before looking at the chat's type, so
--   every send in a group of 5000 cost 60 ms or more, through the messages
--   insert policy and send_text_message alike. It now looks at the type first.
-- * list_conversation_summaries worked out the profile, the member count and
--   the mentions of every chat in the database and used only the caller's.
--   get_conversation_summary worked out the profile of all 5000 members of a
--   group it only needed the title of. Both counted unread messages by
--   reading every message of the chat and dropping the old ones afterwards;
--   now the read marker is a range on the (conversation_id, created_at)
--   index. The counts themselves are exactly the same.
-- * list_circle_summaries joined members x channels x posts to count the
--   distinct ones; each number is now its own subquery. Unread and mention
--   counts use the same range as above.
-- * search_messages(text) read all memberships of the database to find the
--   other person of a direct chat; it now asks per direct chat.
--
-- Everything else in these functions stays as it was: the patches below are
-- text replacements on the live definitions (so a later change by another
-- feature is kept), and each raises if what it expects is not there.

create or replace function pg_temp.l6_patch(fn regprocedure, pairs text[])
returns void
language plpgsql
as $$
declare
  def text := pg_get_functiondef(fn);
  patched text;
  i integer;
begin
  for i in 1..array_length(pairs, 1) by 2 loop
    patched := replace(def, pairs[i], pairs[i + 1]);
    if patched = def then
      raise exception 'L6 patch: expected text not found in %: %', fn, left(pairs[i], 80);
    end if;
    def := patched;
  end loop;
  execute def;
end $$;

-- Same answer as 202610140005_delete_account (a deleted account counts as
-- blocked), but only a direct chat is looked into: a group of 5000 checked
-- 5000 people for blocks on every send.
create or replace function public.is_current_user_blocked_in_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select exists (
        select 1
        from public.conversation_members current_member
        join public.conversation_members other_member
          on other_member.conversation_id = current_member.conversation_id
          and other_member.user_id <> auth.uid()
        join public.profiles other_profile
          on other_profile.id = other_member.user_id
        where current_member.conversation_id = c.id
          and current_member.user_id = auth.uid()
          and (
            public.are_users_blocked(auth.uid(), other_member.user_id)
            or other_profile.deleted_at is not null
          )
      )
      from public.conversations c
      where c.id = target_conversation_id
        and c.type = 'direct'
    ),
    false
  );
$$;

do $do$
begin
  perform pg_temp.l6_patch('public.list_conversation_summaries()'::regprocedure, array[
$old$  unread_counts as (
    select
      rm.conversation_id,
      count(unread_messages.id)
        - count(unread_messages.attachment_group_id)
        + count(distinct unread_messages.attachment_group_id) as unread_count
    from read_markers rm
    join public.messages unread_messages
      on unread_messages.conversation_id = rm.conversation_id
      and unread_messages.review_state is null
      and (unread_messages.expires_at is null or unread_messages.expires_at > now())
      -- A pat is only a line in the chat, never unread.
      and not (
        unread_messages.type = 'system'
        and unread_messages.attachment->>'kind' = 'pat'
      )
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
$old$,
$new$  unread_counts as (
    select rm.conversation_id, u.unread_count
    from read_markers rm
    cross join lateral (
      select
        count(unread_messages.id)
          - count(unread_messages.attachment_group_id)
          + count(distinct unread_messages.attachment_group_id) as unread_count
      from public.messages unread_messages
      where unread_messages.conversation_id = rm.conversation_id
        -- A range on the index (conversation_id, created_at), not a filter
        -- after reading every message of a big chat (L6).
        and unread_messages.created_at
          > coalesce(rm.last_read_at, '-infinity'::timestamptz)
        and unread_messages.review_state is null
        and (unread_messages.expires_at is null or unread_messages.expires_at > now())
        -- A pat is only a line in the chat, never unread.
        and not (
          unread_messages.type = 'system'
          and unread_messages.attachment->>'kind' = 'pat'
        )
        and (
          unread_messages.sender_id <> auth.uid()
          or unread_messages.webhook_name is not null
        )
    ) u
  ),
$new$,
$old$    where cm.user_id <> auth.uid()
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
$old$,
$new$    where cm.user_id <> auth.uid()
      -- Only the caller's own direct chats (L6): the profile of every other
      -- member of every chat in the database was worked out before.
      and cm.conversation_id in (
        select dc.id
        from public.conversations dc
        join current_memberships mine on mine.conversation_id = dc.id
        where dc.type = 'direct'
      )
  ),
  member_counts as (
    select cm.conversation_id, count(*) as member_count
    from public.conversation_members cm
    where cm.conversation_id in (
      select mine.conversation_id from current_memberships mine
    )
    group by cm.conversation_id
  ),
  last_message_mentions as (
    select mm.message_id, array_agg(distinct mm.user_id) as mentioned_user_ids
    from public.message_mentions mm
    where mm.message_id in (
      select lc.last_message_id
      from public.conversations lc
      join current_memberships mine on mine.conversation_id = lc.id
    )
    group by mm.message_id
  )
$new$
  ]);

  perform pg_temp.l6_patch('public.get_conversation_summary(uuid)'::regprocedure, array[
$old$  unread_counts as (
    select
      rm.conversation_id,
      count(unread_messages.id)
        - count(unread_messages.attachment_group_id)
        + count(distinct unread_messages.attachment_group_id) as unread_count
    from read_markers rm
    join public.messages unread_messages
      on unread_messages.conversation_id = rm.conversation_id
      and unread_messages.review_state is null
      and (unread_messages.expires_at is null or unread_messages.expires_at > now())
      -- A pat is only a line in the chat, never unread.
      and not (
        unread_messages.type = 'system'
        and unread_messages.attachment->>'kind' = 'pat'
      )
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
$old$,
$new$  unread_counts as (
    select rm.conversation_id, u.unread_count
    from read_markers rm
    cross join lateral (
      select
        count(unread_messages.id)
          - count(unread_messages.attachment_group_id)
          + count(distinct unread_messages.attachment_group_id) as unread_count
      from public.messages unread_messages
      where unread_messages.conversation_id = rm.conversation_id
        -- A range on the index (conversation_id, created_at), not a filter
        -- after reading every message of a big chat (L6).
        and unread_messages.created_at
          > coalesce(rm.last_read_at, '-infinity'::timestamptz)
        and unread_messages.review_state is null
        and (unread_messages.expires_at is null or unread_messages.expires_at > now())
        -- A pat is only a line in the chat, never unread.
        and not (
          unread_messages.type = 'system'
          and unread_messages.attachment->>'kind' = 'pat'
        )
        and (
          unread_messages.sender_id <> auth.uid()
          or unread_messages.webhook_name is not null
        )
    ) u
  ),
$new$,
$old$    where cm.user_id <> auth.uid()
      and cm.conversation_id = target_conversation_id
  ),
$old$,
$new$    where cm.user_id <> auth.uid()
      and cm.conversation_id = target_conversation_id
      -- Only a direct chat has a person to show (L6): a group of 5000 worked
      -- out 5000 profiles that were never used.
      and exists (
        select 1
        from public.conversations dc
        where dc.id = cm.conversation_id
          and dc.type = 'direct'
      )
  ),
$new$
  ]);

  perform pg_temp.l6_patch('public.list_circle_summaries()'::regprocedure, array[
$old$            and (
              cr.last_read_at is null
              or unread_message.created_at > cr.last_read_at
            )
$old$,
$new$            and unread_message.created_at
              > coalesce(cr.last_read_at, '-infinity'::timestamptz)
$new$,
$old$          and (
            cr.last_read_at is null
            or mentioned_message.created_at > cr.last_read_at
          )
$old$,
$new$          and mentioned_message.created_at
            > coalesce(cr.last_read_at, '-infinity'::timestamptz)
$new$,
$old$    count(distinct all_members.user_id) as member_count,
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
$old$,
$new$    -- Each number on its own (L6): joining members x channels x posts and
    -- counting the distinct ones took 10000 x channels x posts rows.
    (
      select count(*)
      from public.circle_members all_members
      where all_members.circle_id = c.id
    ) as member_count,
    (
      select count(*)
      from visible_channels cc
      where cc.circle_id = c.id
    ) as channel_count,
    greatest(
      c.updated_at,
      coalesce(
        (
          select max(cp.created_at)
          from public.circle_posts cp
          where cp.circle_id = c.id
        ),
        c.updated_at
      ),
      coalesce(
        (
          select max(ch_conversation.last_message_at)
          from visible_channels cc
          join public.conversations ch_conversation
            on ch_conversation.id = cc.conversation_id
          where cc.circle_id = c.id
        ),
        c.updated_at
      )
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
  left join circle_counts counts on counts.circle_id = c.id
  left join public.circle_notification_settings cns
    on cns.circle_id = c.id
    and cns.user_id = auth.uid()
  order by latest_activity_at desc, c.created_at desc;
$new$
  ]);

  perform pg_temp.l6_patch('public.search_messages(text)'::regprocedure, array[
$old$  left join public.conversation_members direct_peer_membership
    on direct_peer_membership.conversation_id = c.id
    and direct_peer_membership.user_id <> auth.uid()
    and c.type = 'direct'
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
$old$,
$new$  -- The other person of a direct chat, looked up for those chats only (L6):
  -- the planner read every membership in the database for it.
  left join lateral (
    select dm.user_id
    from public.conversation_members dm
    where c.type = 'direct'
      and dm.conversation_id = c.id
      and dm.user_id <> auth.uid()
    limit 1
  ) direct_peer_membership on true
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
$new$
  ]);
end $do$;
