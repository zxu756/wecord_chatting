-- Polls, like Discord's: a message of type 'poll' whose attachment holds
-- the question, 2 to 10 options, whether several answers are allowed and
-- when voting ends.
--
-- * messages.type gains 'poll'. Clients cannot insert polls (or system
--   notices) directly: create_poll validates and inserts them, so the send
--   trigger (send_messages and slowmode in circle channels) applies as for
--   any message. body is the question, so previews, notifications and
--   search see it; clients show it as "📊 Poll: <question>".
--   attachment = {kind: 'poll', question, options: [{id, text}], multi,
--   ends_at (null for no end)}.
-- * message_poll_votes: one row per voter and chosen option. Members who
--   can read the conversation see the votes; only RPCs write them.
-- * vote_poll(message_id, option_ids) replaces the caller's votes (exactly
--   one option for single-answer polls, an empty list withdraws them).
--   Polls stop taking votes when they end, are ended early or deleted.
-- * end_poll(message_id): the author, or members with manage_messages in
--   circle channels (and their threads), or the group owner (also in group
--   threads), end a poll early by moving ends_at to now.
-- * poll_results(messages) computed field: {counts {option_id: n},
--   total_voters, my_votes, closed}; list_poll_voters(message_id,
--   option_id) lists who chose an option.
-- * Polls cannot be forwarded (votes belong to the original); search also
--   matches option texts.

alter table public.messages
  drop constraint if exists messages_type_check;

alter table public.messages
  add constraint messages_type_check
  check (type in ('text', 'image', 'file', 'voice', 'system', 'poll'));

-- Same as 202610130002_pinned_messages, but polls are created only by
-- create_poll.
drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type <> 'system'
    and type <> 'poll'
    and forwarded_from is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

create table if not exists public.message_poll_votes (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  option_id text not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, option_id),
  constraint message_poll_votes_option_id_length
    check (char_length(option_id) between 1 and 16)
);

create index if not exists message_poll_votes_conversation_idx
  on public.message_poll_votes (conversation_id);

create index if not exists message_poll_votes_option_idx
  on public.message_poll_votes (message_id, option_id, created_at);

-- Realtime matches DELETE events against the old row, so keep
-- conversation_id in it to let an open thread filter by conversation.
alter table public.message_poll_votes replica identity full;

alter table public.message_poll_votes enable row level security;

revoke insert, update, delete, truncate on public.message_poll_votes from anon;
revoke insert, update, delete, truncate on public.message_poll_votes from authenticated;

drop policy if exists message_poll_votes_select_member on public.message_poll_votes;
create policy message_poll_votes_select_member
  on public.message_poll_votes for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_poll_votes'
  ) then
    alter publication supabase_realtime add table public.message_poll_votes;
  end if;
end $$;

-- Whether a poll message no longer takes votes: deleted, or past its end.
create or replace function public.poll_is_closed(message_row public.messages)
returns boolean
language sql
stable
set search_path = public
as $$
  select message_row.recalled_at is not null
    or (
      message_row.attachment->>'ends_at' is not null
      and (message_row.attachment->>'ends_at')::timestamptz <= now()
    );
$$;

revoke execute on function public.poll_is_closed(public.messages) from public;
revoke execute on function public.poll_is_closed(public.messages) from anon;
revoke execute on function public.poll_is_closed(public.messages) from authenticated;

create or replace function public.create_poll(
  target_conversation_id uuid,
  question text,
  options text[],
  multi boolean default false,
  duration_hours integer default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_question text := btrim(coalesce(question, ''));
  trimmed_options text[];
  option_count integer;
  poll_options jsonb;
  poll_ends_at timestamptz;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_question) not between 1 and 300 then
    raise exception 'Poll question must be 1 to 300 characters'
      using errcode = '22023';
  end if;

  select array_agg(btrim(coalesce(item.option_text, '')) order by item.ordinality)
  into trimmed_options
  from unnest(coalesce(options, array[]::text[]))
    with ordinality as item(option_text, ordinality);

  option_count := coalesce(cardinality(trimmed_options), 0);
  if option_count not between 2 and 10 then
    raise exception 'A poll needs 2 to 10 options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(trimmed_options) as item(option_text)
    where char_length(item.option_text) not between 1 and 100
  ) then
    raise exception 'Poll options must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  if (
    select count(distinct lower(item.option_text))
    from unnest(trimmed_options) as item(option_text)
  ) <> option_count then
    raise exception 'Poll options must be different' using errcode = '22023';
  end if;

  if duration_hours is not null and duration_hours not between 1 and 168 then
    raise exception 'Poll duration must be 1 to 168 hours'
      using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  select jsonb_agg(
    jsonb_build_object('id', 'o' || item.ordinality, 'text', item.option_text)
    order by item.ordinality
  )
  into poll_options
  from unnest(trimmed_options) with ordinality as item(option_text, ordinality);

  if duration_hours is not null then
    poll_ends_at := now() + make_interval(hours => duration_hours);
  end if;

  -- The send trigger checks send_messages and slowmode in circle channels.
  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'poll',
    trimmed_question,
    jsonb_build_object(
      'kind', 'poll',
      'question', trimmed_question,
      'options', poll_options,
      'multi', coalesce(multi, false),
      'ends_at', poll_ends_at
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

create or replace function public.vote_poll(
  target_message_id uuid,
  option_ids text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  poll public.messages%rowtype;
  chosen text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Shares the row with other voters; end_poll waits for them.
  select m.*
  into poll
  from public.messages m
  where m.id = target_message_id
    and m.type = 'poll'
  for share;

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
  then
    raise exception 'Poll not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.poll_is_closed(poll) then
    raise exception 'This poll has ended' using errcode = '22023';
  end if;

  if public.is_current_user_blocked_in_conversation(poll.conversation_id) then
    raise exception 'Cannot vote in this conversation' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct btrim(item.option_id)), array[]::text[])
  into chosen
  from unnest(coalesce(option_ids, array[]::text[])) as item(option_id)
  where item.option_id is not null;

  if exists (
    select 1
    from unnest(chosen) as item(option_id)
    where not exists (
      select 1
      from jsonb_array_elements(poll.attachment->'options') o
      where o->>'id' = item.option_id
    )
  ) then
    raise exception 'Unknown poll option' using errcode = '22023';
  end if;

  if cardinality(chosen) > 1
    and not coalesce((poll.attachment->>'multi')::boolean, false)
  then
    raise exception 'This poll takes one answer' using errcode = '22023';
  end if;

  delete from public.message_poll_votes v
  where v.message_id = poll.id
    and v.user_id = current_user_id
    and not (v.option_id = any(chosen));

  insert into public.message_poll_votes (
    message_id,
    user_id,
    option_id,
    conversation_id
  )
  select poll.id, current_user_id, item.option_id, poll.conversation_id
  from unnest(chosen) as item(option_id)
  on conflict do nothing;
end;
$$;

-- Whether the caller may end someone else's poll in a conversation:
-- manage_messages in circle channels and their threads, the owner in
-- groups and group threads, nobody in direct chats.
create or replace function public.can_current_user_moderate_polls(
  target_conversation_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_id uuid := public.conversation_circle_channel_id(target_conversation_id);
  group_conversation_id uuid;
begin
  if auth.uid() is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    return false;
  end if;

  if channel_id is not null then
    return public.current_user_has_channel_permission(
      channel_id,
      'manage_messages'
    );
  end if;

  select c.id
  into group_conversation_id
  from public.conversations c
  where c.type = 'group'
    and c.id = coalesce(
      (
        select ct.parent_conversation_id
        from public.conversation_threads ct
        where ct.conversation_id = target_conversation_id
      ),
      target_conversation_id
    );

  return group_conversation_id is not null
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = group_conversation_id
        and cm.user_id = auth.uid()
        and cm.role = 'owner'
    );
end;
$$;

create or replace function public.end_poll(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  poll public.messages%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.*
  into poll
  from public.messages m
  where m.id = target_message_id
    and m.type = 'poll'
  for update;

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
    or (
      poll.sender_id <> current_user_id
      and not public.can_current_user_moderate_polls(poll.conversation_id)
    )
  then
    raise exception 'Poll not found or caller cannot end it'
      using errcode = '42501';
  end if;

  if public.poll_is_closed(poll) then
    raise exception 'This poll has ended' using errcode = '22023';
  end if;

  update public.messages m
  set attachment = m.attachment || jsonb_build_object(
    'ends_at', now(),
    'ended_by', current_user_id
  )
  where m.id = poll.id;
end;
$$;

-- PostgREST computed field: `messages?select=*,poll_results` returns, for
-- polls, {counts: {option_id: n}, total_voters, my_votes: [option_id],
-- closed}; null for other messages.
create or replace function public.poll_results(message_row public.messages)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  poll public.messages%rowtype;
  vote_counts jsonb;
  voter_count integer;
  mine jsonb;
begin
  if message_row.type is distinct from 'poll' then
    return null;
  end if;

  -- The stored message, not the row passed in, decides what is shown.
  select m.*
  into poll
  from public.messages m
  where m.id = message_row.id
    and m.type = 'poll';

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
  then
    return null;
  end if;

  select
    coalesce(
      jsonb_object_agg(counted.option_id, counted.vote_count),
      '{}'::jsonb
    )
  into vote_counts
  from (
    select v.option_id, count(*)::integer as vote_count
    from public.message_poll_votes v
    where v.message_id = poll.id
    group by v.option_id
  ) counted;

  select count(distinct v.user_id)::integer
  into voter_count
  from public.message_poll_votes v
  where v.message_id = poll.id;

  select coalesce(jsonb_agg(v.option_id order by v.option_id), '[]'::jsonb)
  into mine
  from public.message_poll_votes v
  where v.message_id = poll.id
    and v.user_id = auth.uid();

  return jsonb_build_object(
    'counts', vote_counts,
    'total_voters', voter_count,
    'my_votes', mine,
    'closed', public.poll_is_closed(poll)
  );
end;
$$;

create or replace function public.list_poll_voters(
  target_message_id uuid,
  target_option_id text
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  created_at timestamptz,
  updated_at timestamptz,
  alias text,
  voted_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.created_at,
    p.updated_at,
    ca.alias,
    v.created_at as voted_at
  from public.message_poll_votes v
  join public.messages m on m.id = v.message_id
  join public.profiles p on p.id = v.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where auth.uid() is not null
    and v.message_id = target_message_id
    and v.option_id = target_option_id
    and m.type = 'poll'
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
  order by v.created_at, p.id;
$$;

-- Same as 202610130002_pinned_messages, but polls cannot be forwarded
-- either: their votes belong to the original.
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
    and type <> 'poll';

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

-- The text search matches: the body, plus a poll's option texts.
create or replace function public.message_search_text(
  message_type text,
  message_body text,
  message_attachment jsonb
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when message_type = 'poll' then concat_ws(
      ' ',
      message_body,
      (
        select string_agg(o->>'text', ' ')
        from jsonb_array_elements(
          case jsonb_typeof(message_attachment->'options')
            when 'array' then message_attachment->'options'
            else '[]'::jsonb
          end
        ) o
      )
    )
    else message_body
  end;
$$;

-- Same as 202610130002_pinned_messages, but polls also match on their
-- options.
create or replace function public.search_messages(
  search_query text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  conversation_title text,
  sender_id uuid,
  sender_name text,
  body text,
  type text,
  created_at timestamptz,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    m.conversation_id,
    coalesce(c.title, peer.display_name) as conversation_title,
    m.sender_id,
    sender.display_name as sender_name,
    m.body,
    m.type,
    m.created_at,
    ts_rank(
      to_tsvector(
        'simple',
        public.message_search_text(m.type, m.body, m.attachment)
      ),
      websearch_to_tsquery('simple', trim(search_query))
    ) as rank
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  join public.profiles sender on sender.id = m.sender_id
  left join public.conversation_members direct_peer_membership
    on direct_peer_membership.conversation_id = c.id
    and direct_peer_membership.user_id <> auth.uid()
    and c.type = 'direct'
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
  where trim(search_query) <> ''
    and m.recalled_at is null
    and m.type <> 'system'
    and public.is_current_user_conversation_member(m.conversation_id)
    and to_tsvector(
        'simple',
        public.message_search_text(m.type, m.body, m.attachment)
      )
      @@ websearch_to_tsquery('simple', trim(search_query))
  order by rank desc, m.created_at desc
  limit 50;
$$;

revoke execute on function public.can_current_user_moderate_polls(uuid) from public;
revoke execute on function public.can_current_user_moderate_polls(uuid) from anon;

grant execute on function public.create_poll(uuid, text, text[], boolean, integer) to authenticated;
grant execute on function public.vote_poll(uuid, text[]) to authenticated;
grant execute on function public.can_current_user_moderate_polls(uuid) to authenticated;
grant execute on function public.end_poll(uuid) to authenticated;
grant execute on function public.poll_results(public.messages) to authenticated;
grant execute on function public.list_poll_voters(uuid, text) to authenticated;
grant execute on function public.forward_message(uuid, uuid) to authenticated;
grant execute on function public.message_search_text(text, text, jsonb) to authenticated;
grant execute on function public.search_messages(text) to authenticated;
