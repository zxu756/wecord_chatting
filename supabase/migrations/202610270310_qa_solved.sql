-- Media channels and Q&A channels (roadmap C9), part 2 of 4: solving a
-- question in a Q&A channel.
--
-- A post of a Q&A channel (kind 'qa') is a question. It can be marked solved,
-- and one answer (a later message of the post) can be picked as the accepted
-- answer.
--
-- * mark_post_solved(thread, answer_message): the asker, or a member with
--   manage_messages in the channel, marks the post solved, optionally with an
--   accepted answer. Marking an already solved post with a different answer
--   moves the mark; marking it again with no answer changes nothing.
--     - The asker needs to be in the circle, not timed out, and the post not
--       locked (C5): a locked post is for moderators. A moderator is not held
--       back by a lock.
--     - Nothing happens while a platform admin has the circle down (K1) or for
--       a suspended account.
--     - The answer must be a message of this post that is not the question
--       itself, not a system notice, not deleted for everyone, not waiting
--       for review (the AI guard's review_state), not expired and not a
--       view-once picture.
--     - The author of the accepted answer gets a push (not for their own
--       answers, not across a block, not twice within a day for one post);
--       when a moderator solves somebody else's question the asker gets one.
--     - Audited as forum_post_solved.
-- * reopen_qa_post(thread): the same people take the mark off. Audited as
--   forum_post_reopened.
-- * get_qa_post_state(conversation): what the post page asks to show the
--   mark and the buttons. null for anything that is not a Q&A post the caller
--   belongs to. Kept apart from the conversation summary on purpose, like
--   get_thread_lock_state.
-- * list_qa_posts: list_forum_posts with a solved / unsolved filter. The
--   forum's own list stays as it is.
-- * forum_post_payload is patched in place (from its current definition, so
--   the album counts, the review_state filters and the bio rule stay) to
--   carry solved_at and solved_message_id for the post list.
-- * claim_qa_answer_pushes(): one row per device, worded in the device's
--   language, taken by scheduled-dispatch once per notice.

-- Whether the actor may mark or reopen a post (the same people for both).
create or replace function public.qa_can_mark_solved(
  thread_row public.conversation_threads,
  channel_row public.circle_channels,
  actor uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if actor is null or thread_row.id is null or channel_row.id is null then
    return false;
  end if;

  if exists (
    select 1 from public.circles c
    where c.id = channel_row.circle_id and c.disabled_at is not null
  ) or public.is_user_suspended(actor) then
    return false;
  end if;

  if not exists (
    select 1 from public.circle_members cm
    where cm.circle_id = channel_row.circle_id and cm.user_id = actor
  ) then
    return false;
  end if;

  if public.user_has_conversation_channel_permission(
    channel_row.conversation_id, actor, 'manage_messages'
  ) then
    return true;
  end if;

  return thread_row.created_by = actor
    and thread_row.locked_at is null
    and exists (
      select 1 from public.circle_members cm
      where cm.circle_id = channel_row.circle_id
        and cm.user_id = actor
        and (cm.timed_out_until is null or cm.timed_out_until <= now())
    )
    and public.user_has_conversation_channel_permission(
      channel_row.conversation_id, actor, 'view_channel'
    );
end;
$$;

revoke execute on function public.qa_can_mark_solved(
  public.conversation_threads, public.circle_channels, uuid
) from public, anon, authenticated;

-- The question itself: the first message of the post that is not a notice.
create or replace function public.qa_opening_message_id(
  target_conversation_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.id
  from public.messages m
  where m.conversation_id = target_conversation_id
    and m.type <> 'system'
  order by m.created_at, m.id
  limit 1;
$$;

revoke execute on function public.qa_opening_message_id(uuid)
  from public, anon, authenticated;

-- Whether a message can be (or still is) the accepted answer of a post.
create or replace function public.qa_answer_is_valid(
  target_conversation_id uuid,
  target_message_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.messages m
    where m.id = target_message_id
      and m.conversation_id = target_conversation_id
      and m.type <> 'system'
      and m.recalled_at is null
      and m.review_state is null
      and (m.expires_at is null or m.expires_at > now())
      and coalesce(m.attachment ->> 'view_once', 'false') <> 'true'
      and m.id is distinct from public.qa_opening_message_id(target_conversation_id)
  );
$$;

revoke execute on function public.qa_answer_is_valid(uuid, uuid)
  from public, anon, authenticated;

-- A push waiting for somebody, unless it would be noise: their own doing, a
-- bot or a deleted account, across a block, somebody who left, or the same
-- news about the same post within a day.
create or replace function public.qa_queue_notice(
  target_user_id uuid,
  target_circle_id uuid,
  target_thread_id uuid,
  notice_kind text,
  actor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_user_id is null or target_user_id = actor_id then
    return false;
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id = target_user_id and (p.is_bot or p.deleted_at is not null)
  ) then
    return false;
  end if;

  if public.are_users_blocked(actor_id, target_user_id) then
    return false;
  end if;

  if not exists (
    select 1 from public.circle_members cm
    where cm.circle_id = target_circle_id and cm.user_id = target_user_id
  ) then
    return false;
  end if;

  if exists (
    select 1 from public.qa_answer_notices n
    where n.user_id = target_user_id
      and n.thread_id = target_thread_id
      and n.kind = notice_kind
      and n.created_at > now() - interval '1 day'
  ) then
    return false;
  end if;

  insert into public.qa_answer_notices (user_id, circle_id, thread_id, kind)
  values (target_user_id, target_circle_id, target_thread_id, notice_kind);
  return true;
end;
$$;

revoke execute on function public.qa_queue_notice(uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated;

-- What the post page shows. Every part is for the caller only.
create or replace function public.get_qa_post_state(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  thread_row public.conversation_threads%rowtype;
  channel_row public.circle_channels%rowtype;
  valid_answer uuid;
begin
  if current_user_id is null then
    return null;
  end if;

  select ct.* into thread_row
  from public.conversation_threads ct
  where ct.conversation_id = target_conversation_id;

  if thread_row.id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    return null;
  end if;

  select cc.* into channel_row
  from public.circle_channels cc
  where cc.conversation_id = thread_row.parent_conversation_id
    and cc.kind = 'qa';

  if channel_row.id is null then
    return null;
  end if;

  if thread_row.solved_message_id is not null
    and public.qa_answer_is_valid(target_conversation_id, thread_row.solved_message_id)
  then
    valid_answer := thread_row.solved_message_id;
  end if;

  return jsonb_build_object(
    'thread_id', thread_row.id,
    'channel_id', channel_row.id,
    'circle_id', channel_row.circle_id,
    'solved', thread_row.solved_at is not null,
    'solved_at', thread_row.solved_at,
    'answer_message_id', valid_answer,
    'opening_message_id', public.qa_opening_message_id(target_conversation_id),
    'can_mark', public.qa_can_mark_solved(thread_row, channel_row, current_user_id)
  );
end;
$$;

revoke execute on function public.get_qa_post_state(uuid) from public, anon;
grant execute on function public.get_qa_post_state(uuid) to authenticated;

create or replace function public.mark_post_solved(
  target_thread_id uuid,
  answer_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  thread_row public.conversation_threads%rowtype;
  channel_row public.circle_channels%rowtype;
  answer_sender uuid;
  moderator_acted boolean;
  queued boolean := false;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ct.* into thread_row
  from public.conversation_threads ct
  where ct.id = target_thread_id
  for update;

  if thread_row.id is null then
    raise exception 'Post not found' using errcode = 'P0002';
  end if;

  select cc.* into channel_row
  from public.circle_channels cc
  where cc.conversation_id = thread_row.parent_conversation_id;

  if channel_row.id is null or channel_row.kind <> 'qa' then
    raise exception 'Only questions in a Q&A channel can be marked solved'
      using errcode = '22023';
  end if;

  if not public.qa_can_mark_solved(thread_row, channel_row, current_user_id) then
    raise exception 'You cannot mark this question solved'
      using errcode = '42501';
  end if;

  if answer_message_id is not null then
    if not public.qa_answer_is_valid(thread_row.conversation_id, answer_message_id) then
      raise exception 'That message cannot be the accepted answer'
        using errcode = '22023';
    end if;
  end if;

  -- Nothing to change.
  if thread_row.solved_at is not null
    and (
      answer_message_id is null
      or thread_row.solved_message_id is not distinct from answer_message_id
    )
  then
    return public.get_qa_post_state(thread_row.conversation_id);
  end if;

  update public.conversation_threads ct
  set solved_at = now(),
      solved_by = current_user_id,
      solved_message_id = answer_message_id
  where ct.id = thread_row.id;

  perform public.write_circle_audit(
    channel_row.circle_id,
    'forum_post_solved',
    'thread',
    thread_row.id,
    thread_row.title,
    jsonb_build_object(
      'channel_id', channel_row.id,
      'channel_name', channel_row.name,
      'created_by', thread_row.created_by,
      'answer_message_id', answer_message_id
    )
  );

  if answer_message_id is not null then
    select m.sender_id into answer_sender
    from public.messages m
    where m.id = answer_message_id;
    queued := public.qa_queue_notice(
      answer_sender,
      channel_row.circle_id,
      thread_row.id,
      'answer_accepted',
      current_user_id
    );
  end if;

  -- A moderator solving somebody else's question tells the asker, unless the
  -- asker is the one whose answer was just accepted (they get that push).
  moderator_acted := thread_row.created_by is distinct from current_user_id;
  if moderator_acted
    and thread_row.created_by is distinct from answer_sender
  then
    queued := public.qa_queue_notice(
      thread_row.created_by,
      channel_row.circle_id,
      thread_row.id,
      'marked_solved',
      current_user_id
    ) or queued;
  end if;

  if queued then
    perform public.wake_scheduled_dispatch();
  end if;

  return public.get_qa_post_state(thread_row.conversation_id);
end;
$$;

revoke execute on function public.mark_post_solved(uuid, uuid)
  from public, anon;
grant execute on function public.mark_post_solved(uuid, uuid) to authenticated;

create or replace function public.reopen_qa_post(target_thread_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  thread_row public.conversation_threads%rowtype;
  channel_row public.circle_channels%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ct.* into thread_row
  from public.conversation_threads ct
  where ct.id = target_thread_id
  for update;

  if thread_row.id is null then
    raise exception 'Post not found' using errcode = 'P0002';
  end if;

  select cc.* into channel_row
  from public.circle_channels cc
  where cc.conversation_id = thread_row.parent_conversation_id;

  if channel_row.id is null or channel_row.kind <> 'qa' then
    raise exception 'Only questions in a Q&A channel can be reopened'
      using errcode = '22023';
  end if;

  if not public.qa_can_mark_solved(thread_row, channel_row, current_user_id) then
    raise exception 'You cannot reopen this question'
      using errcode = '42501';
  end if;

  if thread_row.solved_at is not null then
    update public.conversation_threads ct
    set solved_at = null,
        solved_by = null,
        solved_message_id = null
    where ct.id = thread_row.id;

    perform public.write_circle_audit(
      channel_row.circle_id,
      'forum_post_reopened',
      'thread',
      thread_row.id,
      thread_row.title,
      jsonb_build_object(
        'channel_id', channel_row.id,
        'channel_name', channel_row.name,
        'created_by', thread_row.created_by
      )
    );
  end if;

  return public.get_qa_post_state(thread_row.conversation_id);
end;
$$;

revoke execute on function public.reopen_qa_post(uuid) from public, anon;
grant execute on function public.reopen_qa_post(uuid) to authenticated;

-- A page of a Q&A channel's posts: list_forum_posts
-- (202610130020_forum_channels) plus a solved / unsolved filter. filter_status
-- is null or 'all' for every post, 'solved' or 'unsolved'.
create or replace function public.list_qa_posts(
  target_channel_id uuid,
  sort_order text default 'activity',
  filter_tag_id uuid default null,
  filter_status text default null,
  before_at timestamptz default null,
  before_id uuid default null,
  limit_count integer default 25
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  page_size integer := greatest(1, least(coalesce(limit_count, 25), 100));
  by_created boolean := sort_order = 'created';
  status text := coalesce(filter_status, 'all');
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if sort_order is null or sort_order not in ('activity', 'created') then
    raise exception 'Sort must be activity or created' using errcode = '22023';
  end if;

  if status not in ('all', 'solved', 'unsolved') then
    raise exception 'Status must be all, solved or unsolved'
      using errcode = '22023';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.is_current_user_conversation_member(channel.conversation_id)
  then
    raise exception 'Channel not found or caller cannot see it'
      using errcode = '42501';
  end if;

  if channel.kind <> 'qa' then
    raise exception 'Channel is not a Q&A channel' using errcode = '22023';
  end if;

  return query
  with candidates as (
    select
      ct.id,
      ct.is_pinned,
      case
        when by_created then ct.created_at
        else coalesce(ct.last_message_at, ct.created_at)
      end as sort_at
    from public.conversation_threads ct
    where ct.parent_conversation_id = channel.conversation_id
      and (
        status = 'all'
        or (status = 'solved' and ct.solved_at is not null)
        or (status = 'unsolved' and ct.solved_at is null)
      )
      and (
        filter_tag_id is null
        or exists (
          select 1
          from public.thread_tags tt
          where tt.thread_id = ct.id
            and tt.tag_id = filter_tag_id
        )
      )
  ),
  pinned as (
    select c.id, c.sort_at, 0 as grp
    from candidates c
    where c.is_pinned
      and before_at is null
  ),
  page as (
    select c.id, c.sort_at, 1 as grp
    from candidates c
    where not c.is_pinned
      and (
        before_at is null
        or c.sort_at < before_at
        or (before_id is not null and c.sort_at = before_at and c.id < before_id)
      )
    order by c.sort_at desc, c.id desc
    limit page_size
  ),
  chosen as (
    select * from pinned
    union all
    select * from page
  )
  select public.forum_post_payload(ct, channel)
  from chosen
  join public.conversation_threads ct on ct.id = chosen.id
  order by chosen.grp, chosen.sort_at desc, chosen.id desc;
end;
$$;

revoke execute on function public.list_qa_posts(
  uuid, text, uuid, text, timestamptz, uuid, integer
) from public, anon;
grant execute on function public.list_qa_posts(
  uuid, text, uuid, text, timestamptz, uuid, integer
) to authenticated;

-- forum_post_payload carries the solved mark. Patched from its current
-- definition: the new keys go in front of 'can_manage'.
do $patch$
declare
  target record;
  found_any boolean := false;
  original text;
  patched text;
begin
  for target in
    select p.oid
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'forum_post_payload'
  loop
    found_any := true;
    original := pg_get_functiondef(target.oid);
    patched := replace(
      original,
      '''can_manage'', public.can_current_user_manage_thread(thread_row.id)',
      '''solved_at'', thread_row.solved_at,' || E'\n    '
        || '''solved_message_id'', thread_row.solved_message_id,' || E'\n    '
        || '''can_manage'', public.can_current_user_manage_thread(thread_row.id)'
    );
    if patched = original then
      if original !~ 'solved_message_id' then
        raise exception 'forum_post_payload has no can_manage to put the solved mark before';
      end if;
    else
      execute patched;
    end if;
  end loop;
  if not found_any then
    raise exception 'forum_post_payload does not exist';
  end if;
end;
$patch$;

-- The push for an accepted answer (or a question a moderator marked solved),
-- to the devices of the person, once. One older than 15 minutes when the
-- function gets to it is closed without a push, so a long outage does not end
-- in a burst. Worded in each subscription's language ('en' or 'zh'); names
-- are cleaned of angle brackets, so they cannot pass for a time token. A
-- person who left the circle since, or a circle taken down, gets nothing.
create or replace function public.claim_qa_answer_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  update public.qa_answer_notices n
  set push_claimed_at = now()
  where n.push_claimed_at is null
    and n.created_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.qa_answer_notices n
    set push_claimed_at = now()
    where n.push_claimed_at is null
    returning n.*
  ),
  named as (
    select
      c.id as notice_id,
      c.user_id,
      c.circle_id,
      c.kind,
      ct.conversation_id as post_conversation_id,
      btrim(replace(replace(ct.title, '<', ''), '>', '')) as post_title,
      btrim(replace(replace(ci.name, '<', ''), '>', '')) as circle_name
    from claimed c
    join public.conversation_threads ct on ct.id = c.thread_id
    join public.circles ci on ci.id = c.circle_id and ci.disabled_at is null
    join public.circle_members cm
      on cm.circle_id = c.circle_id and cm.user_id = c.user_id
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case
      when d.kind = 'answer_accepted' and s.language = 'zh' then '你的回答被采纳了'
      when d.kind = 'answer_accepted' then 'Your answer was accepted'
      when s.language = 'zh' then '你的问题已解决'
      else 'Your question was marked solved'
    end,
    case
      when d.kind = 'answer_accepted' and s.language = 'zh' then
        '「' || d.circle_name || '」的问题「' || d.post_title || '」采纳了你的回答。'
      when d.kind = 'answer_accepted' then
        'Your answer to "' || d.post_title || '" in ' || d.circle_name
          || ' was accepted.'
      when s.language = 'zh' then
        '版主把「' || d.circle_name || '」里的问题「' || d.post_title
          || '」标为了已解决。'
      else
        'A moderator marked "' || d.post_title || '" in ' || d.circle_name
          || ' as solved.'
    end,
    'qa-' || d.notice_id::text,
    '/#/circles/' || d.circle_id::text || '/channels/'
      || d.post_conversation_id::text
  from named d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_qa_answer_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_qa_answer_pushes() to service_role;
