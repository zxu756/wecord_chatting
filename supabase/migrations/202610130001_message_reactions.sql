create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji),
  constraint message_reactions_emoji_length
    check (char_length(emoji) between 1 and 64)
);

create index if not exists message_reactions_conversation_idx
  on public.message_reactions (conversation_id);

-- Realtime matches DELETE events against the old row, so keep conversation_id
-- in it to let an open thread filter reaction removals by conversation.
alter table public.message_reactions replica identity full;

alter table public.message_reactions enable row level security;

create policy message_reactions_select_member
  on public.message_reactions for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end $$;

-- PostgREST computed field: `messages?select=*,reactions` returns
-- [{emoji, count, reacted_by_me}] for every listed message.
create or replace function public.reactions(message_row public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'emoji', grouped.emoji,
        'count', grouped.reaction_count,
        'reacted_by_me', grouped.reacted_by_me
      )
      order by grouped.first_reacted_at, grouped.emoji
    ),
    '[]'::jsonb
  )
  from (
    select
      mr.emoji,
      count(*)::integer as reaction_count,
      coalesce(bool_or(mr.user_id = auth.uid()), false) as reacted_by_me,
      min(mr.created_at) as first_reacted_at
    from public.message_reactions mr
    join public.messages m on m.id = mr.message_id
    where mr.message_id = message_row.id
      and m.recalled_at is null
      and public.is_current_user_conversation_member(mr.conversation_id)
    group by mr.emoji
  ) grouped;
$$;

create or replace function public.toggle_message_reaction(
  target_message_id uuid,
  target_emoji text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_emoji text := btrim(coalesce(target_emoji, ''));
  target_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(normalized_emoji) not between 1 and 64 then
    raise exception 'Reaction emoji must be 1 to 64 characters'
      using errcode = '22023';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = target_message_id
    and m.recalled_at is null;

  if target_conversation_id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Message not found or caller is not a member'
      using errcode = '42501';
  end if;

  delete from public.message_reactions
  where message_id = target_message_id
    and user_id = current_user_id
    and emoji = normalized_emoji;

  if found then
    return false;
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Message cannot be reacted to' using errcode = '42501';
  end if;

  insert into public.message_reactions (
    message_id,
    user_id,
    emoji,
    conversation_id
  )
  values (
    target_message_id,
    current_user_id,
    normalized_emoji,
    target_conversation_id
  )
  on conflict do nothing;

  return true;
end;
$$;

create or replace function public.list_message_reactors(
  target_message_id uuid,
  target_emoji text
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
  reacted_at timestamptz
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
    mr.created_at as reacted_at
  from public.message_reactions mr
  join public.messages m on m.id = mr.message_id
  join public.profiles p on p.id = mr.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where mr.message_id = target_message_id
    and mr.emoji = btrim(coalesce(target_emoji, ''))
    and m.recalled_at is null
    and public.is_current_user_conversation_member(mr.conversation_id)
  order by mr.created_at, p.id;
$$;

grant execute on function public.reactions(public.messages) to authenticated;
grant execute on function public.toggle_message_reaction(uuid, text) to authenticated;
grant execute on function public.list_message_reactors(uuid, text) to authenticated;
