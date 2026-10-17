-- Saved messages ("Later"): a personal list of messages to come back to.
--
-- * saved_messages: one row per user and message (RLS: owner only for
--   select and delete; rows are written through save_message and
--   set_saved_message_done, which check the caller can see the message).
--   The message may go away later (the id is cleared when it is deleted);
--   the entry stays, as "Message unavailable", until the user removes it.
-- * list_saved_messages: the caller's saved messages with the message as
--   the caller may see it. It runs as the caller, so messages and profiles
--   keep their own policies: a deleted message, or one in a conversation or
--   channel the caller can no longer read, comes back with available =
--   false and no text.
-- * done_at marks an entry done (and null makes it active again).

create table if not exists public.saved_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  done_at timestamptz
);

create unique index if not exists saved_messages_user_message_key
  on public.saved_messages (user_id, message_id)
  where message_id is not null;

create index if not exists saved_messages_user_idx
  on public.saved_messages (user_id, created_at desc);

alter table public.saved_messages enable row level security;

revoke all on public.saved_messages from anon, authenticated;
grant select, delete on public.saved_messages to authenticated;

drop policy if exists saved_messages_select_own on public.saved_messages;
create policy saved_messages_select_own
  on public.saved_messages for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists saved_messages_delete_own on public.saved_messages;
create policy saved_messages_delete_own
  on public.saved_messages for delete
  to authenticated
  using (user_id = auth.uid());

-- Saves a message the caller can see. Saving it again changes nothing.
create or replace function public.save_message(p_message_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_conversation_id uuid;
  saved_id uuid;
  saved_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = p_message_id
    and m.recalled_at is null
    and m.conversation_id in (select public.current_user_readable_conversation_ids());
  if target_conversation_id is null then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  select s.id
  into saved_id
  from public.saved_messages s
  where s.user_id = current_user_id
    and s.message_id = p_message_id;
  if saved_id is not null then
    return saved_id;
  end if;

  select count(*)
  into saved_count
  from public.saved_messages s
  where s.user_id = current_user_id;
  if saved_count >= 1000 then
    raise exception 'Too many saved messages' using errcode = '53400';
  end if;

  insert into public.saved_messages (user_id, message_id, conversation_id)
  values (current_user_id, p_message_id, target_conversation_id)
  on conflict do nothing
  returning id into saved_id;

  if saved_id is null then
    select s.id
    into saved_id
    from public.saved_messages s
    where s.user_id = current_user_id
      and s.message_id = p_message_id;
  end if;
  return saved_id;
end;
$$;

revoke execute on function public.save_message(uuid) from public, anon;
grant execute on function public.save_message(uuid) to authenticated;

-- Marks a saved message done, or active again.
create or replace function public.set_saved_message_done(p_id uuid, p_done boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.saved_messages s
  set done_at = case when coalesce(p_done, true) then coalesce(s.done_at, now()) else null end
  where s.id = p_id
    and s.user_id = auth.uid();
end;
$$;

revoke execute on function public.set_saved_message_done(uuid, boolean) from public, anon;
grant execute on function public.set_saved_message_done(uuid, boolean) to authenticated;

create or replace function public.list_saved_messages(p_limit integer default 500)
returns table (
  saved_id uuid,
  message_id uuid,
  conversation_id uuid,
  saved_at timestamptz,
  done_at timestamptz,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  webhook_name text,
  body text,
  type text,
  message_created_at timestamptz,
  available boolean
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    s.id,
    s.message_id,
    s.conversation_id,
    s.created_at,
    s.done_at,
    case when m.recalled_at is null then m.sender_id end,
    case when m.recalled_at is null then p.display_name end,
    case when m.recalled_at is null then p.avatar_url end,
    case when m.recalled_at is null then m.webhook_name end,
    case when m.recalled_at is null then m.body end,
    case when m.recalled_at is null then m.type end,
    case when m.recalled_at is null then m.created_at end,
    m.id is not null and m.recalled_at is null
  from public.saved_messages s
  left join public.messages m on m.id = s.message_id
  left join public.profiles p on p.id = m.sender_id
  where s.user_id = auth.uid()
  order by s.created_at desc, s.id
  limit greatest(1, least(coalesce(p_limit, 500), 1000));
$$;

revoke execute on function public.list_saved_messages(integer) from public, anon;
grant execute on function public.list_saved_messages(integer) to authenticated;
