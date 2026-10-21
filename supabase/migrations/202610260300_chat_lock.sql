-- App lock and chat lock (roadmap G2): what the server needs to know.
--
-- The lock itself is on the device: Face ID, Touch ID or the device passcode
-- on iPhone and Mac, a PIN in the browser. The server never sees a PIN, a
-- secret code or whether a chat is hidden from the list. It only needs to
-- know WHICH chats the person locked, for three reasons:
--
--   * a push about a locked chat shows no sender and no text, on every device
--     of the person (the lock screen is the very place a borrowed phone is
--     read);
--   * the daily digest (F3) leaves a locked chat out, and the digest cards
--     already made do not list it;
--   * AI questions (F1) never search a locked chat.
--
-- The list is kept in the person's notification settings row (A4,
-- 202610210300), so every device of the person agrees on it:
--
--   user_notification_settings.locked_conversation_ids uuid[]
--
-- * Only the person's own direct and group chats can be locked (a circle
--   channel is not a private conversation). The trigger checks it for the
--   app's writes; an id that is dropped from the list when the person leaves
--   the chat.
-- * set_conversation_locked(chat, locked) adds or removes one chat without
--   the app having to read and rewrite the whole list.
-- * is_conversation_locked(person, chat): whether the person locked the chat,
--   or the parent chat of a thread. Internal (service role and the functions
--   below).
-- * locked_chat_push_text(pairs): for the push functions. Given
--   {subscription_id, conversation_id} pairs it answers the pairs whose
--   subscription belongs to a person who locked that chat, with the title and
--   body to send in place of the real ones, worded in the subscription's
--   language ('en' or 'zh').
-- * The three functions that read chat content for a person are patched in
--   place (their newest definitions, read with pg_get_functiondef) to leave
--   locked chats out: ai_digest_messages, list_my_ai_digests and
--   ai_ask_conversations.

alter table public.user_notification_settings
  add column if not exists locked_conversation_ids uuid[] not null default '{}';

alter table public.user_notification_settings
  drop constraint if exists user_notification_settings_locked_check;
alter table public.user_notification_settings
  add constraint user_notification_settings_locked_check
  check (cardinality(locked_conversation_ids) <= 200);

-- Keeps the list tidy (no duplicates) and, for the person's own writes, lets
-- them add only their own direct and group chats.
create or replace function public.user_notification_settings_locked_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  added uuid[];
begin
  new.locked_conversation_ids := coalesce(
    (select array_agg(distinct c) from unnest(new.locked_conversation_ids) c),
    '{}'
  );

  if tg_op = 'UPDATE' then
    added := array(
      select c from unnest(new.locked_conversation_ids) c
      except
      select c from unnest(old.locked_conversation_ids) c
    );
  else
    added := new.locked_conversation_ids;
  end if;

  if auth.uid() is not null and cardinality(added) > 0 and exists (
    select 1
    from unnest(added) c
    where not exists (
      select 1
      from public.conversation_members m
      join public.conversations cv on cv.id = m.conversation_id
      where m.conversation_id = c
        and m.user_id = new.user_id
        and cv.type in ('direct', 'group')
    )
  ) then
    raise exception 'Only your own direct and group chats can be locked'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke execute on function public.user_notification_settings_locked_before_write()
  from public, anon, authenticated;

drop trigger if exists user_notification_settings_locked_before_write
  on public.user_notification_settings;
create trigger user_notification_settings_locked_before_write
  before insert or update of locked_conversation_ids
  on public.user_notification_settings
  for each row execute function public.user_notification_settings_locked_before_write();

-- Leaving a chat (or being removed) takes it out of the person's locked list.
create or replace function public.forget_locked_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_notification_settings s
  set locked_conversation_ids = array_remove(s.locked_conversation_ids, old.conversation_id)
  where s.user_id = old.user_id
    and old.conversation_id = any(s.locked_conversation_ids);
  return old;
end;
$$;

revoke execute on function public.forget_locked_conversation()
  from public, anon, authenticated;

drop trigger if exists conversation_members_forget_locked on public.conversation_members;
create trigger conversation_members_forget_locked
  after delete on public.conversation_members
  for each row execute function public.forget_locked_conversation();

-- Locks or unlocks one chat for the caller, creating the row when needed.
create or replace function public.set_conversation_locked(
  target_conversation_id uuid,
  locked boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if target_conversation_id is null then
    raise exception 'Choose a chat' using errcode = '22023';
  end if;

  if locked then
    if not exists (
      select 1
      from public.conversation_members m
      join public.conversations cv on cv.id = m.conversation_id
      where m.conversation_id = target_conversation_id
        and m.user_id = me
        and cv.type in ('direct', 'group')
    ) then
      raise exception 'Only your own direct and group chats can be locked'
        using errcode = '23514';
    end if;
    insert into public.user_notification_settings as s (user_id, locked_conversation_ids)
    values (me, array[target_conversation_id])
    on conflict (user_id) do update
    set locked_conversation_ids = array_append(
      array_remove(s.locked_conversation_ids, target_conversation_id),
      target_conversation_id
    );
  else
    update public.user_notification_settings s
    set locked_conversation_ids = array_remove(
      s.locked_conversation_ids,
      target_conversation_id
    )
    where s.user_id = me;
  end if;
end;
$$;

revoke execute on function public.set_conversation_locked(uuid, boolean) from public, anon;
grant execute on function public.set_conversation_locked(uuid, boolean) to authenticated;

-- Whether [p_user_id] locked [p_conversation_id], or the chat a thread
-- belongs to.
create or replace function public.is_conversation_locked(
  p_user_id uuid,
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_notification_settings s
    where s.user_id = p_user_id
      and cardinality(s.locked_conversation_ids) > 0
      and (
        p_conversation_id = any(s.locked_conversation_ids)
        or exists (
          select 1
          from public.conversation_threads ct
          where ct.conversation_id = p_conversation_id
            and ct.parent_conversation_id = any(s.locked_conversation_ids)
        )
      )
  );
$$;

revoke execute on function public.is_conversation_locked(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.is_conversation_locked(uuid, uuid) to service_role;

-- For the push functions: the text that replaces the real title and body of
-- a push about a locked chat. [target_pairs] is
-- [{"subscription_id": ..., "conversation_id": ...}, ...]; the pairs whose
-- subscription belongs to a person who locked that chat come back, with a
-- title and body that say only that something came, in the subscription's
-- language.
create or replace function public.locked_chat_push_text(
  target_pairs jsonb
)
returns table (
  subscription_id uuid,
  conversation_id uuid,
  title text,
  body text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.id,
    p.conversation_id,
    'WeCord',
    case
      when s.language = 'zh' then '你收到一条新消息'
      else 'You have a new message'
    end
  from jsonb_to_recordset(
    case when jsonb_typeof(target_pairs) = 'array' then target_pairs else '[]'::jsonb end
  ) as p(subscription_id uuid, conversation_id uuid)
  join public.push_subscriptions s on s.id = p.subscription_id
  where p.conversation_id is not null
    and public.is_conversation_locked(s.user_id, p.conversation_id);
$$;

revoke execute on function public.locked_chat_push_text(jsonb)
  from public, anon, authenticated;
grant execute on function public.locked_chat_push_text(jsonb) to service_role;

-- The three readers of chat content, patched in place so nothing they gained
-- since is lost. Each patch must find its anchor and change the text, or the
-- migration stops and says so.
do $$
declare
  def text;
  patched text;
begin
  -- The messages a person's daily digest may cover (202610230520).
  def := pg_get_functiondef('public.ai_digest_messages(uuid, timestamptz, timestamptz)'::regprocedure);
  if def not like '%is_conversation_locked%' then
    patched := replace(
      def,
      E'      and public.conversation_ai_assistant_allowed(s.conversation_id)\n',
      E'      and public.conversation_ai_assistant_allowed(s.conversation_id)\n      and not public.is_conversation_locked(p_user_id, s.conversation_id)\n'
    );
    if patched = def or patched not like '%is_conversation_locked%' then
      raise exception 'ai_digest_messages changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The digest cards already made (202610230510).
  def := pg_get_functiondef('public.list_my_ai_digests()'::regprocedure);
  if def not like '%is_conversation_locked%' then
    patched := replace(
      def,
      E'      )\n  ) kept\n',
      E'      )\n      and not public.is_conversation_locked(me, x.conversation_id)\n  ) kept\n'
    );
    if patched = def or patched not like '%is_conversation_locked%' then
      raise exception 'list_my_ai_digests changed shape; patch it by hand';
    end if;
    execute patched;
  end if;

  -- The chats an AI question may search (202610250300).
  def := pg_get_functiondef('public.ai_ask_conversations(uuid, jsonb)'::regprocedure);
  if def not like '%is_conversation_locked%' then
    patched := replace(
      def,
      E'    where public.conversation_ai_assistant_allowed(s.id)\n',
      E'    where public.conversation_ai_assistant_allowed(s.id)\n      and not public.is_conversation_locked(p_user_id, s.id)\n'
    );
    if patched = def or patched not like '%is_conversation_locked%' then
      raise exception 'ai_ask_conversations changed shape; patch it by hand';
    end if;
    execute patched;
  end if;
end;
$$;
