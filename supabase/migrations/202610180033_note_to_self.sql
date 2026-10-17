-- Note to self (文件传输助手): a chat that only you are in, for sending text,
-- photos, files and voice between your own phone and computer.
--
-- It is an ordinary direct conversation with ONE member (the owner), made
-- the first time it is asked for (get_note_to_self) and never more than one
-- per user. Sending, uploading, editing, search, reactions, pins, notes and
-- the rest work through the same code as any chat, because they only ask
-- "is the caller a member?".
--
-- What it does not do:
--
-- * No read receipts and no typing: receipts and typing come from the other
--   members, and there are none; the app also leaves both out.
-- * Never an unread badge: unread counts only messages from other people
--   (list_conversation_summaries), and every message here is the owner's
--   own, also when it was sent from another device.
-- * No push, not even to your other devices: claim_push_delivery pushes to
--   members other than the sender, and there is no other member. Pushes do
--   not know which device sent a message, so "push the other device only"
--   cannot be done; none is sent.
-- * Nobody can be added: a trigger refuses a second member (add_group_members
--   only works on groups, and direct chats are made by
--   get_or_create_direct_conversation, which needs two people).
--
-- Deleting the account removes the chat with it (on delete cascade).

create table if not exists public.note_to_self_conversations (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  conversation_id uuid not null unique
    references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.note_to_self_conversations enable row level security;
revoke all on public.note_to_self_conversations from anon, authenticated;

drop policy if exists note_to_self_select_own on public.note_to_self_conversations;
create policy note_to_self_select_own
  on public.note_to_self_conversations for select
  to authenticated
  using (user_id = auth.uid());
grant select on public.note_to_self_conversations to authenticated;

-- A note to self never takes a second member.
create or replace function public.note_to_self_only_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.note_to_self_conversations n
    where n.conversation_id = new.conversation_id
      and n.user_id <> new.user_id
  ) then
    raise exception 'Nobody else can join a note to self'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists conversation_members_note_to_self_only_owner
  on public.conversation_members;
create trigger conversation_members_note_to_self_only_owner
  before insert or update of user_id, conversation_id
  on public.conversation_members
  for each row execute function public.note_to_self_only_owner();

revoke execute on function public.note_to_self_only_owner() from public, anon, authenticated;

-- The caller's note to self: its conversation id, made when it does not
-- exist yet and create_if_missing is true (the default); null when it does
-- not exist and create_if_missing is false.
create or replace function public.get_note_to_self(
  create_if_missing boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  existing_id uuid;
  new_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select n.conversation_id into existing_id
  from public.note_to_self_conversations n
  where n.user_id = current_user_id;
  if existing_id is not null or not coalesce(create_if_missing, true) then
    return existing_id;
  end if;

  -- Two devices opening it for the first time at once make one chat.
  perform pg_advisory_xact_lock(
    hashtextextended('note-to-self:' || current_user_id::text, 0)
  );

  select n.conversation_id into existing_id
  from public.note_to_self_conversations n
  where n.user_id = current_user_id;
  if existing_id is not null then
    return existing_id;
  end if;

  insert into public.conversations (type, title)
  values ('direct', 'Note to self')
  returning id into new_id;

  insert into public.note_to_self_conversations (user_id, conversation_id)
  values (current_user_id, new_id);

  insert into public.conversation_members (
    conversation_id, user_id, role, pinned_at
  )
  values (new_id, current_user_id, 'owner', now());

  return new_id;
end;
$$;

revoke execute on function public.get_note_to_self(boolean) from public, anon;
grant execute on function public.get_note_to_self(boolean) to authenticated;
