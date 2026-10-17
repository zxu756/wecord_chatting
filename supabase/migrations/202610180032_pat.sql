-- Pat-pat (拍一拍): double-tap someone's avatar in a direct or group chat.
--
-- A pat is a light system line in the chat: "You patted Ada", "Bart patted
-- you", "Bart patted Ada" (what others in a group see). The line is a
-- messages row of type 'system' whose attachment is
--   {kind: 'pat', actor_id, target_id, actor_name, target_name, suffix,
--    undone?, undone_at?}
-- and clients draw the sentence from it, in the viewer's language and from
-- the viewer's side (202610180034_chat_list_pat_note.sql keeps a pat out of
-- unread counts and out of the conversation's latest message; pushes already
-- skip system lines other than calls, see claim_push_delivery, so a pat never
-- notifies anyone: the receiver sees the line and a gentle shake of the
-- avatar when the chat is open, nothing more).
--
-- * Suffix. Each user can set a short "Pat suffix" (at most 20 characters,
--   e.g. "'s shoulder" or "的肩膀"). It is stored with the line when someone
--   pats that user, so it reads "You patted Ada's shoulder".
-- * Rate limits, server side: once per 10 seconds per pair (the same person
--   patting the same person), 20 per hour per pair, and 100 per hour in all
--   for one person. Undoing a pat does not give the allowance back.
-- * Respect: no pats between people where either blocked the other, not
--   towards deleted accounts, only between members of a direct or group chat
--   (never in circle channels and threads, where the AI guard's review state
--   (messages.review_state) and channel rules apply; a pat line is made by the
--   server and never takes part in a review), and not by anyone who may not
--   send in the chat. A muted chat still gets the line, but nobody is shaken
--   or pushed (the client leaves the shake out when the chat is muted).
-- * Undo. The patter can take a pat back within 2 minutes: the line then
--   reads "X took back a pat" for everyone.
-- * The table takes no direct reads or writes; pat_user, undo_pat,
--   get_my_pat_suffix and set_my_pat_suffix are the only ways in.

create table if not exists public.pat_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  suffix text not null default '',
  updated_at timestamptz not null default now(),
  constraint pat_settings_suffix_length check (char_length(suffix) <= 20)
);

alter table public.pat_settings enable row level security;
revoke all on public.pat_settings from anon, authenticated;

create table if not exists public.chat_pats (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.messages(id) on delete cascade,
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  target_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists chat_pats_pair_idx
  on public.chat_pats (actor_id, target_id, created_at desc);
create index if not exists chat_pats_actor_idx
  on public.chat_pats (actor_id, created_at desc);
create index if not exists chat_pats_message_idx
  on public.chat_pats (message_id)
  where message_id is not null;

alter table public.chat_pats enable row level security;
revoke all on public.chat_pats from anon, authenticated;

-- The caller's suffix ('' when none).
create or replace function public.get_my_pat_suffix()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select s.suffix from public.pat_settings s where s.user_id = auth.uid()),
    ''
  );
$$;

-- Saves the caller's suffix: trimmed of the space around it, no line breaks
-- or other control characters, at most 20 characters. '' clears it.
create or replace function public.set_my_pat_suffix(new_suffix text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  cleaned text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  cleaned := btrim(regexp_replace(coalesce(new_suffix, ''), '[[:cntrl:]]', '', 'g'));
  if char_length(cleaned) > 20 then
    raise exception 'The suffix is too long (20 characters at most)'
      using errcode = '22023';
  end if;

  insert into public.pat_settings as s (user_id, suffix, updated_at)
  values (current_user_id, cleaned, now())
  on conflict (user_id) do update
  set suffix = excluded.suffix, updated_at = now();

  return cleaned;
end;
$$;

-- Pats target_user_id in target_conversation_id. Returns
-- {message_id, created_at, suffix}.
create or replace function public.pat_user(
  target_conversation_id uuid,
  target_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  conversation_type text;
  actor_name text;
  target_name text;
  target_suffix text;
  new_message_id uuid;
  new_created_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'Pat someone else' using errcode = '22023';
  end if;

  select c.type into conversation_type
  from public.conversations c
  where c.id = target_conversation_id;

  if conversation_type is null or conversation_type not in ('direct', 'group') then
    raise exception 'You can pat people in direct and group chats'
      using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id)
    or not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = target_conversation_id
        and cm.user_id = target_user_id
    )
  then
    raise exception 'Conversation not found or not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id)
    or public.are_users_blocked(current_user_id, target_user_id)
    or exists (
      select 1 from public.profiles p
      where p.id = target_user_id and p.deleted_at is not null
    )
  then
    raise exception 'You cannot pat this person' using errcode = '42501';
  end if;

  -- Takes turns per person, so two quick pats cannot both pass the checks.
  perform pg_advisory_xact_lock(
    hashtextextended('pat:' || current_user_id::text, 0)
  );

  if exists (
    select 1 from public.chat_pats cp
    where cp.actor_id = current_user_id
      and cp.target_id = target_user_id
      and cp.created_at > now() - interval '10 seconds'
  ) then
    raise exception 'pat_too_fast' using errcode = '53400',
      hint = 'You can pat the same person once every 10 seconds';
  end if;

  if (
    select count(*) from public.chat_pats cp
    where cp.actor_id = current_user_id
      and cp.target_id = target_user_id
      and cp.created_at > now() - interval '1 hour'
  ) >= 20
    or (
      select count(*) from public.chat_pats cp
      where cp.actor_id = current_user_id
        and cp.created_at > now() - interval '1 hour'
    ) >= 100
  then
    raise exception 'pat_too_many' using errcode = '53400',
      hint = 'That is a lot of pats for now; try again later';
  end if;

  select coalesce(nullif(btrim(p.display_name), ''), p.username)
  into actor_name
  from public.profiles p where p.id = current_user_id;

  select coalesce(nullif(btrim(p.display_name), ''), p.username)
  into target_name
  from public.profiles p where p.id = target_user_id;

  select coalesce(
    (select s.suffix from public.pat_settings s where s.user_id = target_user_id),
    ''
  ) into target_suffix;

  insert into public.messages (
    conversation_id, sender_id, type, body, attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'system',
    coalesce(actor_name, 'Someone') || ' patted '
      || coalesce(target_name, 'someone') || target_suffix,
    jsonb_build_object(
      'kind', 'pat',
      'actor_id', current_user_id,
      'target_id', target_user_id,
      'actor_name', coalesce(actor_name, ''),
      'target_name', coalesce(target_name, ''),
      'suffix', target_suffix
    )
  )
  returning id, created_at into new_message_id, new_created_at;

  insert into public.chat_pats (
    message_id, conversation_id, actor_id, target_id, created_at
  )
  values (
    new_message_id,
    target_conversation_id,
    current_user_id,
    target_user_id,
    new_created_at
  );

  return jsonb_build_object(
    'message_id', new_message_id,
    'created_at', new_created_at,
    'suffix', target_suffix
  );
end;
$$;

-- Takes the caller's pat back within 2 minutes.
create or replace function public.undo_pat(target_message_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  pat public.messages%rowtype;
  actor_name text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.* into pat
  from public.messages m
  where m.id = target_message_id
    and m.type = 'system'
    and m.attachment->>'kind' = 'pat'
    and m.sender_id = current_user_id;

  if pat.id is null then
    raise exception 'Pat not found' using errcode = '42501';
  end if;

  if coalesce((pat.attachment->>'undone')::boolean, false) then
    return;
  end if;

  if pat.created_at < now() - interval '2 minutes' then
    raise exception 'pat_undo_expired' using errcode = '22023',
      hint = 'A pat can be taken back within 2 minutes';
  end if;

  select coalesce(nullif(btrim(p.display_name), ''), p.username)
  into actor_name
  from public.profiles p where p.id = current_user_id;

  update public.messages m
  set body = coalesce(actor_name, 'Someone') || ' took back a pat',
    attachment = m.attachment || jsonb_build_object(
      'undone', true,
      'undone_at', now()
    )
  where m.id = pat.id;
end;
$$;

revoke execute on function public.get_my_pat_suffix() from public, anon;
revoke execute on function public.set_my_pat_suffix(text) from public, anon;
revoke execute on function public.pat_user(uuid, uuid) from public, anon;
revoke execute on function public.undo_pat(uuid) from public, anon;
grant execute on function public.get_my_pat_suffix() to authenticated;
grant execute on function public.set_my_pat_suffix(text) to authenticated;
grant execute on function public.pat_user(uuid, uuid) to authenticated;
grant execute on function public.undo_pat(uuid) to authenticated;
