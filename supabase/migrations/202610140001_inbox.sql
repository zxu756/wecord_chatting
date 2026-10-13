-- Inbox: recent messages that mention the current user (directly or through
-- @all) or reply to one of their messages, newest first. Runs as the caller
-- so the messages policy hides conversations and channels they cannot read.

create index if not exists message_mentions_user_created_idx
  on public.message_mentions (user_id, created_at desc);

create index if not exists messages_reply_to_idx
  on public.messages (reply_to_message_id)
  where reply_to_message_id is not null;

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
      case when bool_or(mm.kind = 'user') then 'mention' else 'mention_all' end
        as reason
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
  )
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    p.display_name,
    p.avatar_url,
    m.webhook_name,
    m.body,
    m.type,
    m.created_at,
    hits.reason,
    m.created_at > coalesce(last_read.created_at, '-infinity'::timestamptz)
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
  order by m.created_at desc, m.id desc
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke execute on function public.list_inbox(integer) from public;
revoke execute on function public.list_inbox(integer) from anon;
grant execute on function public.list_inbox(integer) to authenticated;
