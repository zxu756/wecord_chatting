-- Urgent messages and announcements that need a confirmation (A7, part 1 of 4):
-- the tables.
--
-- Urgent messages. The sender of a message can mark it urgent for chosen
-- members of the conversation ("Urgent" in the message menu):
--
--   * message_urgents: one row for each time the sender did it. The sender
--     may do it 5 times in any 24 hours (send_message_urgent counts these).
--   * message_urgent_targets: one row for each person told. They are
--     confirmed ("Got it") by the person, or the row waits and the push is
--     sent a second time 10 minutes after the first (never a third time).
--     A message urgent for a person once is not urgent for them again.
--   * urgent_sender_mutes: a person who turned urgent messages off for one
--     sender. Their messages then never reach that person as urgent.
--
-- Announcements that need a confirmation. A group's owner or admin can ask
-- members to confirm the announcement ("Ask members to confirm"):
--
--   * conversations.announcement_requires_ack
--   * announcement_acks: who confirmed. A change of the announcement text, or
--     switching the request off, clears them, so a confirmation is always for
--     the text the member saw.
--   * announcement_ack_reminders: the "please confirm" pushes waiting to go
--     out (see 202610240430). The member list and the reminder button are
--     the manager's; every member sees the count and their own state.
--   * conversations.announcement_ack_reminded_at: when the managers last
--     reminded, which limits how often they can.
--
-- Nothing here is open to clients except reading one's own urgent rows (so
-- the app learns of a new urgent message through Realtime): the writes go
-- through the functions of 202610240410 and 202610240420.

-- --------------------------------------------------------------- urgents

create table if not exists public.message_urgents (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists message_urgents_sender_idx
  on public.message_urgents (sender_id, created_at desc);

create index if not exists message_urgents_message_idx
  on public.message_urgents (message_id);

create table if not exists public.message_urgent_targets (
  urgent_id uuid not null references public.message_urgents(id) on delete cascade,
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  acked_at timestamptz,
  -- When the first push was claimed, and the second (re-)push.
  push_claimed_at timestamptz,
  repush_claimed_at timestamptz,
  primary key (urgent_id, user_id),
  -- A person is made urgent for a message once.
  unique (message_id, user_id)
);

create index if not exists message_urgent_targets_user_idx
  on public.message_urgent_targets (user_id, created_at desc)
  where acked_at is null;

create index if not exists message_urgent_targets_push_idx
  on public.message_urgent_targets (created_at)
  where acked_at is null and repush_claimed_at is null;

create table if not exists public.urgent_sender_mutes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, sender_id),
  check (user_id <> sender_id)
);

alter table public.message_urgents enable row level security;
alter table public.message_urgent_targets enable row level security;
alter table public.urgent_sender_mutes enable row level security;

revoke all on public.message_urgents from public, anon, authenticated;
revoke all on public.message_urgent_targets from public, anon, authenticated;
revoke all on public.urgent_sender_mutes from public, anon, authenticated;

grant select on public.message_urgents to authenticated;
grant select on public.message_urgent_targets to authenticated;
grant select on public.urgent_sender_mutes to authenticated;

-- The sender sees their own (that it was used, and so the quota).
drop policy if exists message_urgents_select_sender on public.message_urgents;
create policy message_urgents_select_sender
  on public.message_urgents for select
  to authenticated
  using (sender_id = auth.uid());

-- A person sees the rows about them: the app listens to these through
-- Realtime to raise the banner as soon as the message is made urgent.
drop policy if exists message_urgent_targets_select_own on public.message_urgent_targets;
create policy message_urgent_targets_select_own
  on public.message_urgent_targets for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists urgent_sender_mutes_select_own on public.urgent_sender_mutes;
create policy urgent_sender_mutes_select_own
  on public.urgent_sender_mutes for select
  to authenticated
  using (user_id = auth.uid());

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'message_urgent_targets'
    )
  then
    alter publication supabase_realtime add table public.message_urgent_targets;
  end if;
end;
$$;

-- --------------------------------------------------------- announcements

alter table public.conversations
  add column if not exists announcement_requires_ack boolean not null default false,
  add column if not exists announcement_ack_reminded_at timestamptz;

create table if not exists public.announcement_acks (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  acked_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists announcement_acks_user_idx
  on public.announcement_acks (user_id);

-- "Please confirm" pushes: one row for each member asked, handed out once by
-- claim_announcement_ack_pushes.
create table if not exists public.announcement_ack_reminders (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  pushed_at timestamptz
);

create index if not exists announcement_ack_reminders_push_idx
  on public.announcement_ack_reminders (created_at)
  where pushed_at is null;

alter table public.announcement_acks enable row level security;
alter table public.announcement_ack_reminders enable row level security;
revoke all on public.announcement_acks from public, anon, authenticated;
revoke all on public.announcement_ack_reminders from public, anon, authenticated;

-- A confirmation is for the text the member saw: changing the announcement,
-- or turning the request off, clears them. (Turning it on again starts
-- fresh.) The text is compared the way update_group_profile stores it.
create or replace function public.announcement_acks_reset()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(old.announcement, '') is distinct from coalesce(new.announcement, '')
    or (old.announcement_requires_ack and not new.announcement_requires_ack)
  then
    delete from public.announcement_acks a where a.conversation_id = new.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.announcement_acks_reset()
  from public, anon, authenticated;

drop trigger if exists conversations_announcement_acks_reset on public.conversations;
create trigger conversations_announcement_acks_reset
  after update of announcement, announcement_requires_ack on public.conversations
  for each row execute function public.announcement_acks_reset();
