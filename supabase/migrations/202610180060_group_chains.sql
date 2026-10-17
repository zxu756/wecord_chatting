-- Group chains (接龙): a sign-up list that lives in a group or a circle
-- channel, as one card in the chat that everybody fills in.
--
-- * chains: one row per chain. The card in the chat is an ordinary text
--   message whose body is "🔗 <title>" (so search, previews and pushes just
--   work) and whose attachment is {kind: 'chain', chain_id, title}; the chat
--   renders it as the live list. A chain is closed when closed_at is set or
--   its deadline has passed; max_entries caps the list.
-- * chain_entries: one line per person per chain (unique chain_id, user_id).
--   The line is "N. <name> <optional note>"; N is the order of joining.
--   People edit or remove their own line; the creator and moderators
--   (manage_messages in circle channels, the owner in groups: the same people
--   who may end a poll) remove anyone's line and close or reopen the chain.
-- * Nothing is written by clients directly: all changes go through
--   create_chain / join_chain / update_chain_entry / leave_chain /
--   remove_chain_entry / set_chain_closed, which check membership, whether the
--   person may send there, the deadline, the cap and one line per person.
--   get_chain reads everything for a card in one go.
-- * Live updates: every change to an entry touches the chain's row
--   (entry_count, updated_at), and chains is in the supabase_realtime
--   publication, so a client subscribes to chains of its conversation and
--   re-reads get_chain: no message per entry. (Deletes cannot be filtered
--   in Realtime, an update of the chain row can.)
-- * AI guard: when a circle has the guard on and the person still counts as
--   new there, the free text they send is not let through unreviewed: they
--   may join, but the note of their line is dropped (join_chain /
--   update_chain_entry answer note_held = true). The chain card itself is a
--   message and goes through the guard like any other.

create table if not exists public.chains (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  example text not null default '',
  deadline timestamptz,
  max_entries integer,
  entry_count integer not null default 0,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chains_title_length check (char_length(title) between 1 and 120),
  constraint chains_description_length check (char_length(description) <= 1000),
  constraint chains_example_length check (char_length(example) <= 200),
  constraint chains_max_entries_range check (max_entries is null or max_entries between 1 and 500)
);

create index if not exists chains_conversation_idx
  on public.chains (conversation_id, created_at desc);

create table if not exists public.chain_entries (
  id uuid primary key default gen_random_uuid(),
  chain_id uuid not null references public.chains(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  note text not null default '',
  -- clock_timestamp, not now(): the order of joining is the order of the
  -- lines, even for two joins in one transaction.
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint chain_entries_note_length check (char_length(note) <= 200),
  constraint chain_entries_one_per_person unique (chain_id, user_id)
);

create index if not exists chain_entries_chain_idx
  on public.chain_entries (chain_id, created_at, id);

alter table public.chains enable row level security;
alter table public.chain_entries enable row level security;

revoke all on public.chains from anon, authenticated;
revoke all on public.chain_entries from anon, authenticated;
grant select on public.chains to authenticated;
grant select on public.chain_entries to authenticated;

drop policy if exists chains_select on public.chains;
create policy chains_select on public.chains
  for select to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

drop policy if exists chain_entries_select on public.chain_entries;
create policy chain_entries_select on public.chain_entries
  for select to authenticated
  using (
    exists (
      select 1
      from public.chains c
      where c.id = chain_entries.chain_id
        and public.is_current_user_conversation_member(c.conversation_id)
    )
  );

-- Every change of a line touches the chain, which is what Realtime sends.
create or replace function public.chain_entries_touch_chain()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.chain_id, old.chain_id);
begin
  update public.chains c
  set entry_count = (
        select count(*)::integer from public.chain_entries e where e.chain_id = c.id
      ),
      updated_at = clock_timestamp()
  where c.id = target;
  return null;
end;
$$;

drop trigger if exists chain_entries_touch on public.chain_entries;
create trigger chain_entries_touch
  after insert or update or delete on public.chain_entries
  for each row execute function public.chain_entries_touch_chain();

-- Whether the chain no longer takes changes.
create or replace function public.chain_is_closed(chain_row public.chains)
returns boolean
language sql
stable
as $$
  select chain_row.closed_at is not null
    or (chain_row.deadline is not null and chain_row.deadline <= now());
$$;

-- Chains live in groups and circle channels (and their threads), not in
-- direct chats.
create or replace function public.chain_conversation_allowed(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = target_conversation_id
      and (
        c.type in ('group', 'channel')
        or (
          c.type = 'thread'
          and exists (
            select 1
            from public.conversation_threads t
            join public.conversations parent on parent.id = t.parent_conversation_id
            where t.conversation_id = c.id
              and parent.type in ('group', 'channel')
          )
        )
      )
  );
$$;

-- Whether the caller may change or remove the lines of others in
-- [chain_row]: the creator, and whoever moderates the conversation.
create or replace function public.chain_can_manage(chain_row public.chains)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  return chain_row.created_by = auth.uid()
    or public.can_current_user_moderate_polls(chain_row.conversation_id);
end;
$$;

-- Whether the free text of [p_user_id] in [p_conversation_id] would wait for
-- the AI guard: the same rule as messages_review_guard (a circle with the
-- guard on and AI allowed, a member who still counts as new and is no bot,
-- moderator or manager).
create or replace function public.chain_note_needs_review(
  p_conversation_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  guard public.circle_ai_guard%rowtype;
  joined_at timestamptz;
begin
  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(p_conversation_id);
  if channel_circle_id is null then
    return false;
  end if;

  select g.* into guard
  from public.circle_ai_guard g
  where g.circle_id = channel_circle_id and g.enabled;
  if guard.circle_id is null then
    return false;
  end if;

  if not exists (
    select 1 from public.circles c where c.id = channel_circle_id and c.ai_enabled
  ) then
    return false;
  end if;

  select cm.created_at into joined_at
  from public.circle_members cm
  where cm.circle_id = channel_circle_id and cm.user_id = p_user_id;
  if joined_at is null then
    return false;
  end if;

  if exists (select 1 from public.profiles p where p.id = p_user_id and p.is_bot)
    or public.circle_member_has_permission(channel_circle_id, p_user_id, 'manage_messages')
    or public.circle_member_has_permission(channel_circle_id, p_user_id, 'manage_circle')
  then
    return false;
  end if;

  if guard.new_rule = 'joined_days' then
    return joined_at > now() - make_interval(days => guard.joined_days);
  end if;

  return (
    select count(*)
    from (
      select 1
      from public.messages m
      where m.sender_id = p_user_id
        and m.recalled_at is null
        and m.review_state is null
        and m.conversation_id in (
          select cc.conversation_id
          from public.circle_channels cc
          where cc.circle_id = channel_circle_id
          union all
          select ct.conversation_id
          from public.conversation_threads ct
          join public.circle_channels cc
            on cc.conversation_id = ct.parent_conversation_id
          where cc.circle_id = channel_circle_id
        )
      limit guard.message_count
    ) counted
  ) < guard.message_count;
end;
$$;

-- Creates a chain and posts its card into [target_conversation_id].
-- Answers {chain_id, message_id}.
create or replace function public.create_chain(
  target_conversation_id uuid,
  chain_title text,
  chain_description text default null,
  chain_example text default null,
  chain_deadline timestamptz default null,
  chain_max_entries integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  clean_title text := btrim(coalesce(chain_title, ''));
  clean_description text := btrim(coalesce(chain_description, ''));
  clean_example text := btrim(coalesce(chain_example, ''));
  new_chain_id uuid := gen_random_uuid();
  new_message_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  if not public.chain_conversation_allowed(target_conversation_id) then
    raise exception 'chain_not_allowed' using errcode = '22023';
  end if;
  if not public.can_current_user_send_in_conversation(target_conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if char_length(clean_title) not between 1 and 120 then
    raise exception 'chain_title_invalid' using errcode = '22023';
  end if;
  if char_length(clean_description) > 1000 or char_length(clean_example) > 200 then
    raise exception 'chain_text_too_long' using errcode = '22023';
  end if;
  if chain_deadline is not null
    and (chain_deadline <= now() or chain_deadline > now() + interval '366 days')
  then
    raise exception 'chain_deadline_invalid' using errcode = '22023';
  end if;
  if chain_max_entries is not null and chain_max_entries not between 1 and 500 then
    raise exception 'chain_max_invalid' using errcode = '22023';
  end if;

  insert into public.chains (
    id, conversation_id, created_by, title, description, example, deadline, max_entries
  )
  values (
    new_chain_id, target_conversation_id, uid, clean_title, clean_description,
    clean_example, chain_deadline, chain_max_entries
  );

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    uid,
    'text',
    E'\U0001F517 ' || clean_title,
    jsonb_build_object('kind', 'chain', 'chain_id', new_chain_id, 'title', clean_title)
  )
  returning id into new_message_id;

  update public.chains set message_id = new_message_id where id = new_chain_id;

  return jsonb_build_object('chain_id', new_chain_id, 'message_id', new_message_id);
end;
$$;

-- Everything a chain card shows, in one read: the chain, its numbered lines
-- (in the order people joined) and what the caller may do.
create or replace function public.get_chain(target_chain_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  c public.chains%rowtype;
  channel_circle_id uuid;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;

  select cc.circle_id into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(c.conversation_id);

  select jsonb_build_object(
    'id', c.id,
    'conversation_id', c.conversation_id,
    'message_id', c.message_id,
    'title', c.title,
    'description', c.description,
    'example', c.example,
    'deadline', c.deadline,
    'max_entries', c.max_entries,
    'entry_count', c.entry_count,
    'closed', public.chain_is_closed(c),
    'closed_at', c.closed_at,
    'created_by', c.created_by,
    'created_at', c.created_at,
    'creator_name', coalesce(
      nullif(btrim(creator_member.nickname), ''),
      nullif(btrim(creator.display_name), ''),
      creator.username
    ),
    'can_manage', public.chain_can_manage(c),
    'my_entry_id', (
      select e.id from public.chain_entries e
      where e.chain_id = c.id and e.user_id = auth.uid()
    ),
    'entries', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', e.id,
          'user_id', e.user_id,
          'name', coalesce(
            nullif(btrim(member.nickname), ''),
            nullif(btrim(p.display_name), ''),
            p.username,
            ''
          ),
          'avatar_url', coalesce(member.avatar_url, p.avatar_url),
          'note', e.note,
          'created_at', e.created_at,
          'updated_at', e.updated_at
        )
        order by e.created_at, e.id
      )
      from public.chain_entries e
      join public.profiles p on p.id = e.user_id
      left join public.circle_members member
        on member.circle_id = channel_circle_id and member.user_id = e.user_id
      where e.chain_id = c.id
    ), '[]'::jsonb)
  )
  into result
  from public.profiles creator
  left join public.circle_members creator_member
    on creator_member.circle_id = channel_circle_id
    and creator_member.user_id = creator.id
  where creator.id = c.created_by;

  return result;
end;
$$;

-- Adds the caller's line. One line per person: edit it with
-- update_chain_entry, or remove it with leave_chain first.
create or replace function public.join_chain(
  target_chain_id uuid,
  entry_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.chains%rowtype;
  clean_note text := btrim(coalesce(entry_note, ''));
  held boolean := false;
  new_entry_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_send_in_conversation(c.conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(c.conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if public.chain_is_closed(c) then
    raise exception 'chain_closed' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.chain_entries e where e.chain_id = c.id and e.user_id = uid
  ) then
    raise exception 'chain_already_joined' using errcode = '23505';
  end if;
  if c.max_entries is not null and c.entry_count >= c.max_entries then
    raise exception 'chain_full' using errcode = 'P0001';
  end if;
  if char_length(clean_note) > 200 then
    raise exception 'chain_text_too_long' using errcode = '22023';
  end if;
  if clean_note <> '' and public.chain_note_needs_review(c.conversation_id, uid) then
    clean_note := '';
    held := true;
  end if;

  insert into public.chain_entries (chain_id, user_id, note)
  values (c.id, uid, clean_note)
  returning id into new_entry_id;

  return jsonb_build_object('entry_id', new_entry_id, 'note_held', held);
end;
$$;

-- Changes the note of the caller's own line.
create or replace function public.update_chain_entry(
  target_chain_id uuid,
  entry_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.chains%rowtype;
  clean_note text := btrim(coalesce(entry_note, ''));
  held boolean := false;
  changed integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if public.chain_is_closed(c) then
    raise exception 'chain_closed' using errcode = 'P0001';
  end if;
  if char_length(clean_note) > 200 then
    raise exception 'chain_text_too_long' using errcode = '22023';
  end if;
  if clean_note <> '' and public.chain_note_needs_review(c.conversation_id, uid) then
    clean_note := '';
    held := true;
  end if;

  update public.chain_entries
  set note = clean_note, updated_at = now()
  where chain_id = c.id and user_id = uid;
  get diagnostics changed = row_count;
  if changed = 0 then
    raise exception 'chain_not_joined' using errcode = 'P0002';
  end if;

  return jsonb_build_object('note_held', held);
end;
$$;

-- Removes the caller's own line.
create or replace function public.leave_chain(target_chain_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.chains%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if public.chain_is_closed(c) then
    raise exception 'chain_closed' using errcode = 'P0001';
  end if;
  delete from public.chain_entries where chain_id = c.id and user_id = uid;
end;
$$;

-- The creator or a moderator removes anybody's line (also after the chain
-- closed, to tidy the final list).
create or replace function public.remove_chain_entry(target_entry_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.chains%rowtype;
  entry public.chain_entries%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into entry from public.chain_entries where id = target_entry_id;
  if entry.id is null then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  select * into c from public.chains where id = entry.chain_id for update;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if entry.user_id <> auth.uid() and not public.chain_can_manage(c) then
    raise exception 'Only the creator or a moderator can remove other lines'
      using errcode = '42501';
  end if;
  delete from public.chain_entries where id = entry.id;
end;
$$;

-- Closes a chain, or reopens it (an expired deadline is dropped so that it
-- stays open).
create or replace function public.set_chain_closed(
  target_chain_id uuid,
  closed boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.chains%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null or not public.is_current_user_conversation_member(c.conversation_id) then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if not public.chain_can_manage(c) then
    raise exception 'Only the creator or a moderator can close a chain'
      using errcode = '42501';
  end if;

  if closed then
    update public.chains
    set closed_at = coalesce(closed_at, now()), closed_by = auth.uid(), updated_at = now()
    where id = c.id;
  else
    update public.chains
    set closed_at = null,
        closed_by = null,
        deadline = case when deadline <= now() then null else deadline end,
        updated_at = now()
    where id = c.id;
  end if;
end;
$$;

revoke execute on function public.chain_entries_touch_chain() from public, anon, authenticated;
revoke execute on function public.chain_conversation_allowed(uuid) from public, anon, authenticated;
revoke execute on function public.chain_can_manage(public.chains) from public, anon, authenticated;
revoke execute on function public.chain_note_needs_review(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.chain_is_closed(public.chains) from public, anon;

revoke execute on function public.create_chain(uuid, text, text, text, timestamptz, integer) from public, anon;
revoke execute on function public.get_chain(uuid) from public, anon;
revoke execute on function public.join_chain(uuid, text) from public, anon;
revoke execute on function public.update_chain_entry(uuid, text) from public, anon;
revoke execute on function public.leave_chain(uuid) from public, anon;
revoke execute on function public.remove_chain_entry(uuid) from public, anon;
revoke execute on function public.set_chain_closed(uuid, boolean) from public, anon;

grant execute on function public.chain_is_closed(public.chains) to authenticated;
grant execute on function public.create_chain(uuid, text, text, text, timestamptz, integer) to authenticated;
grant execute on function public.get_chain(uuid) to authenticated;
grant execute on function public.join_chain(uuid, text) to authenticated;
grant execute on function public.update_chain_entry(uuid, text) to authenticated;
grant execute on function public.leave_chain(uuid) to authenticated;
grant execute on function public.remove_chain_entry(uuid) to authenticated;
grant execute on function public.set_chain_closed(uuid, boolean) to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'chains'
    )
  then
    alter publication supabase_realtime add table public.chains;
  end if;
end;
$$;
