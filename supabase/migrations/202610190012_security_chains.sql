-- Security audit (2026-10-19): a chain follows its card.
--
-- A chain is a row of its own next to a card message. The card goes through
-- the AI guard like any text message, but the chain did not: while a new
-- member's card waited for review (or after it was deleted, or when it
-- expired in a disappearing group) every member could still read the chain
-- (title, description, example, lines) from the chains table, from get_chain
-- and from Realtime, and join it.
--
-- * chain_card_visible(message id): the card exists, is not deleted or
--   expired, and the caller may read it (not held, unless they sent it or
--   moderate). The chains and chain_entries select policies and every chain
--   function ask it.
-- * create_chain: the description and the example are free text that is no
--   part of the card's body, so the guard never saw them. For a member the
--   guard would hold they are dropped (text_held = true), the way the note of
--   a line is dropped by join_chain.

create or replace function public.chain_card_visible(card_message_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select card_message_id is not null
    and exists (
      select 1
      from public.messages m
      where m.id = card_message_id
        and m.recalled_at is null
        and (m.expires_at is null or m.expires_at > now())
        and public.message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)
    );
$$;

revoke execute on function public.chain_card_visible(uuid) from public, anon;
grant execute on function public.chain_card_visible(uuid) to authenticated;

drop policy if exists chains_select on public.chains;
create policy chains_select on public.chains
  for select to authenticated
  using (
    public.is_current_user_conversation_member(conversation_id)
    and public.chain_card_visible(message_id)
  );

drop policy if exists chain_entries_select on public.chain_entries;
create policy chain_entries_select on public.chain_entries
  for select to authenticated
  using (
    exists (
      select 1
      from public.chains c
      where c.id = chain_entries.chain_id
        and public.is_current_user_conversation_member(c.conversation_id)
        and public.chain_card_visible(c.message_id)
    )
  );

CREATE OR REPLACE FUNCTION public.get_chain(target_chain_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c public.chains%rowtype;
  channel_circle_id uuid;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id;
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
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
$function$;

CREATE OR REPLACE FUNCTION public.join_chain(target_chain_id uuid, entry_note text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
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
$function$;

CREATE OR REPLACE FUNCTION public.update_chain_entry(target_chain_id uuid, entry_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
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
$function$;

CREATE OR REPLACE FUNCTION public.leave_chain(target_chain_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  c public.chains%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if public.chain_is_closed(c) then
    raise exception 'chain_closed' using errcode = 'P0001';
  end if;
  delete from public.chain_entries where chain_id = c.id and user_id = uid;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_chain_closed(target_chain_id uuid, closed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c public.chains%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.chains where id = target_chain_id for update;
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
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
$function$;

CREATE OR REPLACE FUNCTION public.remove_chain_entry(target_entry_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if c.id is null
    or not public.is_current_user_conversation_member(c.conversation_id)
    or not public.chain_card_visible(c.message_id)
  then
    raise exception 'Chain not found' using errcode = 'P0002';
  end if;
  if entry.user_id <> auth.uid() and not public.chain_can_manage(c) then
    raise exception 'Only the creator or a moderator can remove other lines'
      using errcode = '42501';
  end if;
  delete from public.chain_entries where id = entry.id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.create_chain(target_conversation_id uuid, chain_title text, chain_description text DEFAULT NULL::text, chain_example text DEFAULT NULL::text, chain_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone, chain_max_entries integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  clean_title text := btrim(coalesce(chain_title, ''));
  clean_description text := btrim(coalesce(chain_description, ''));
  clean_example text := btrim(coalesce(chain_example, ''));
  new_chain_id uuid := gen_random_uuid();
  new_message_id uuid;
  text_held boolean := false;
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

  -- The description and the example are not part of the card's text, which
  -- is what the AI guard reads: for a member it would hold, they are dropped.
  if (clean_description <> '' or clean_example <> '')
    and public.chain_note_needs_review(target_conversation_id, uid)
  then
    clean_description := '';
    clean_example := '';
    text_held := true;
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

  return jsonb_build_object(
    'chain_id', new_chain_id,
    'message_id', new_message_id,
    'text_held', text_held
  );
end;
$function$;
