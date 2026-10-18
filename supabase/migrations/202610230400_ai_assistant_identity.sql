-- The @WeCord AI assistant, part 1 of 3 (roadmap F2): who it is, what marks
-- its replies, and the group owner's switch.
--
-- * public.system_bots: the app's own bot accounts, by key ('wecord_ai').
--   The assistant is a bot identity like the ones circle managers make
--   (profiles.is_bot, 202610160030), but it belongs to no circle and is never
--   a member of any chat: when someone @mentions it, the `ai` function posts
--   its answer as this account. Nothing here holds a user id; the account is
--   created at run time (below), so every environment gets its own.
-- * How the account is created: SQL may not insert into auth.users on hosted
--   projects (202610160031 explains), so the `ai` function creates the login
--   with the Auth admin API the first time it needs it (banned, provider
--   'bot', exactly what the `bots` function does) and then calls
--   register_ai_assistant, service role only. That function checks the login
--   is such a bot login made in the last ten minutes with no profile yet,
--   takes a lock, and is idempotent: when the assistant already exists it
--   returns that one and the function deletes the surplus login.
-- * messages.ai_reply: set on the assistant's replies only, by the server. It
--   says who asked and what kind of answer it is ({requester_id,
--   requester_name, kind: answer|summary|translation|rewrite|todos, items?}).
--   The app shows "AI-generated" and, for todos, "Make tasks" from it. A
--   trigger refuses any client that tries to write it, so a person cannot dress
--   a message up as an AI answer.
-- * public.group_ai_settings: the group owner's "Allow WeCord AI in this
--   group" switch. A missing row means allowed. Members read it, only the
--   owner of a group changes it, through set_group_ai_assistant.
-- * conversation_ai_assistant_allowed(conversation): the assistant's version
--   of conversation_ai_allowed (202610170031) that does not need a signed-in
--   caller: the circle's AI switch (for a thread, its parent channel's circle)
--   and the group switch. The person's own switch is user_ai_settings.

create table if not exists public.system_bots (
  key text primary key check (key ~ '^[a-z][a-z0-9_]{0,31}$'),
  user_id uuid not null unique references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

alter table public.system_bots enable row level security;
revoke all on public.system_bots from anon, authenticated;
grant select on public.system_bots to authenticated;

drop policy if exists system_bots_select on public.system_bots;
create policy system_bots_select
  on public.system_bots for select
  to authenticated
  using (true);

-- The assistant's account, or null before it was first needed.
create or replace function public.ai_assistant_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select b.user_id from public.system_bots b where b.key = 'wecord_ai';
$$;

revoke execute on function public.ai_assistant_user_id() from public, anon;
grant execute on function public.ai_assistant_user_id() to authenticated, service_role;

-- Turns the bot login the `ai` function just made into the assistant's
-- profile. Returns the assistant's user id: the given one, or the existing
-- one when another call was first (then the caller removes its login).
create or replace function public.register_ai_assistant(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  existing uuid;
  chosen_username text := 'wecord_ai';
begin
  perform pg_advisory_xact_lock(hashtextextended('system_bot:wecord_ai', 0));

  select b.user_id into existing from public.system_bots b where b.key = 'wecord_ai';
  if existing is not null then
    return existing;
  end if;

  if p_user_id is null
    or not exists (
      select 1
      from auth.users u
      where u.id = p_user_id
        and u.raw_app_meta_data->>'provider' = 'bot'
        and u.created_at > now() - interval '10 minutes'
    )
    or exists (select 1 from public.profiles p where p.id = p_user_id)
  then
    raise exception 'The assistant account is not ready' using errcode = '22023';
  end if;

  -- Somebody may have taken the plain name already.
  if exists (select 1 from public.profiles p where lower(p.username) = chosen_username) then
    chosen_username := 'wecord_ai_' || substr(replace(p_user_id::text, '-', ''), 1, 6);
  end if;

  insert into public.profiles (id, username, display_name, is_bot)
  values (p_user_id, chosen_username, 'WeCord AI', true);

  insert into public.system_bots (key, user_id) values ('wecord_ai', p_user_id);
  return p_user_id;
end;
$$;

revoke execute on function public.register_ai_assistant(uuid) from public, anon, authenticated;
grant execute on function public.register_ai_assistant(uuid) to service_role;

-- ------------------------------------------------------------ ai_reply mark

alter table public.messages
  add column if not exists ai_reply jsonb;

alter table public.messages
  drop constraint if exists messages_ai_reply_object;
alter table public.messages
  add constraint messages_ai_reply_object check (
    ai_reply is null or jsonb_typeof(ai_reply) = 'object'
  );

create or replace function public.messages_guard_ai_reply()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') and (
    (tg_op = 'INSERT' and new.ai_reply is not null)
    or (tg_op = 'UPDATE' and new.ai_reply is distinct from old.ai_reply)
  ) then
    raise exception 'Only the server marks AI replies' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_guard_ai_reply on public.messages;
create trigger messages_guard_ai_reply
  before insert or update of ai_reply on public.messages
  for each row execute function public.messages_guard_ai_reply();

-- ------------------------------------------------------- the group's switch

create table if not exists public.group_ai_settings (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  assistant_enabled boolean not null default true,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.group_ai_settings enable row level security;
revoke all on public.group_ai_settings from anon, authenticated;
grant select on public.group_ai_settings to authenticated;

drop policy if exists group_ai_settings_select on public.group_ai_settings;
create policy group_ai_settings_select
  on public.group_ai_settings for select
  to authenticated
  using (public.is_current_user_conversation_member(conversation_id));

-- Whether the assistant answers in a group; true when nobody changed it.
create or replace function public.get_group_ai_assistant(target_conversation_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;
  return coalesce(
    (select s.assistant_enabled
     from public.group_ai_settings s
     where s.conversation_id = target_conversation_id),
    true
  );
end;
$$;

-- The owner of a group allows or forbids WeCord AI in it.
create or replace function public.set_group_ai_assistant(
  target_conversation_id uuid,
  enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = target_conversation_id
      and c.type = 'group'
      and cm.user_id = auth.uid()
      and cm.role = 'owner'
  ) then
    raise exception 'Only the owner of a group can change this' using errcode = '42501';
  end if;

  insert into public.group_ai_settings (conversation_id, assistant_enabled, updated_by)
  values (target_conversation_id, coalesce(enabled, true), auth.uid())
  on conflict (conversation_id) do update
  set assistant_enabled = excluded.assistant_enabled,
      updated_by = excluded.updated_by,
      updated_at = now();
  return coalesce(enabled, true);
end;
$$;

revoke execute on function public.get_group_ai_assistant(uuid) from public, anon;
grant execute on function public.get_group_ai_assistant(uuid) to authenticated;
revoke execute on function public.set_group_ai_assistant(uuid, boolean) from public, anon;
grant execute on function public.set_group_ai_assistant(uuid, boolean) to authenticated;

-- ---------------------------------------------- may the assistant answer here

-- The circle's switch and the group's switch, for the assistant, which
-- answers without a caller's token. A thread follows its parent channel or
-- group. Internal.
create or replace function public.conversation_ai_assistant_allowed(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  with scope as (
    select coalesce(
      (select ct.parent_conversation_id
       from public.conversation_threads ct
       where ct.conversation_id = target_conversation_id),
      target_conversation_id
    ) as conversation_id
  )
  select
    coalesce(
      (select c.ai_enabled
       from public.circle_channels cc
       join public.circles c on c.id = cc.circle_id
       join scope on cc.conversation_id = scope.conversation_id
       limit 1),
      true
    )
    and coalesce(
      (select s.assistant_enabled
       from public.group_ai_settings s
       join scope on s.conversation_id = scope.conversation_id),
      true
    );
$$;

revoke execute on function public.conversation_ai_assistant_allowed(uuid)
  from public, anon, authenticated;
grant execute on function public.conversation_ai_assistant_allowed(uuid) to service_role;
