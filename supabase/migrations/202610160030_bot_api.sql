-- A bot API: circle managers create bot accounts that external programs
-- drive through the `bot-api` Edge Function with a secret token. See
-- docs/bot-api.md for the HTTP side.
--
-- * profiles.is_bot marks bot accounts (shown with a BOT badge). Only the
--   server sets it. A bot is a real profile backed by an auth user that
--   cannot sign in (no email or password, banned forever), so it can be a
--   circle member and send messages like anyone else.
-- * circle_bots: one row per bot, tied to one circle. Only a SHA-256 hash
--   of the token is stored (null once revoked); the token is returned once
--   by create_circle_bot / regenerate_bot_token. Clients cannot read the
--   table: list_circle_bots returns everything but the hash.
-- * Managing bots needs manage_circle (202610160020). A role given at
--   creation must be
--   one the creator could assign (manage_roles and below their rank). At
--   most 10 bots per circle. Audited as bot_create, bot_regenerate,
--   bot_revoke and bot_delete. Deleting a bot removes it from the circle;
--   its profile stays so its messages keep their author.
-- * Everything a bot does goes through the same checks as a member: the
--   bot_api_* functions (service_role only, for the Edge Function) look up
--   the bot by token, make sure it is still a member of its circle, then
--   act as the bot (request.jwt.claims) and call the existing functions
--   (send_text_message, toggle_message_reaction) or the permission
--   functions (view_channel, send_messages, timeouts and slowmode
--   included), so AutoMod checks bots too: a message it refuses quietly
--   comes back as a null id. Writes are limited to 60 per bot and minute
--   (BT429).
-- * Slash commands: a bot registers up to 25 commands (bot_commands,
--   names unique per circle). Members see them in the composer
--   (list_circle_bot_commands); using one (invoke_bot_command) records a
--   bot_interactions row instead of sending a message: the member needs
--   send_messages in the channel, and the bot must see and post in it. The
--   bot polls for interactions (bot_api_poll_interactions, at-least-once:
--   an interaction is handed out again 30 seconds after a poll until it is
--   answered) and answers each once within 15 minutes
--   (bot_api_respond_interaction), which posts its message with
--   messages.interaction = {interaction_id, command, user_id, user_name}
--   so clients show who used which command. Polling was picked over
--   outgoing webhooks: bots need no public URL and nothing here makes
--   outbound requests.
--
-- Error codes, mapped to HTTP by the function: 28000 bad or revoked token
-- (401), 42501 not allowed (403), P0002 not found (404), 22023 invalid
-- input (400), 23505 conflict (409), BT429 or slowmode P0001 (429).

alter table public.profiles
  add column if not exists is_bot boolean not null default false;

create or replace function public.profiles_guard_is_bot()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon')
    and new.is_bot is distinct from (
      case when tg_op = 'INSERT' then false else old.is_bot end
    )
  then
    raise exception 'Only the server marks bot accounts' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_is_bot on public.profiles;
create trigger profiles_guard_is_bot
  before insert or update of is_bot on public.profiles
  for each row execute function public.profiles_guard_is_bot();

alter table public.messages
  add column if not exists interaction jsonb;

alter table public.messages
  drop constraint if exists messages_interaction_object;
alter table public.messages
  add constraint messages_interaction_object check (
    interaction is null or jsonb_typeof(interaction) = 'object'
  );

-- Same as 202610160027_announcement_channels, plus interaction.
create or replace function public.messages_guard_server_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon')
    and (
      new.crosspost is not null
      or new.published_at is not null
      or new.interaction is not null
    )
  then
    raise exception 'These message fields are set by the server'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create table if not exists public.circle_bots (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  name text not null,
  token_hash text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  constraint circle_bots_name_length check (
    name = btrim(name) and char_length(name) between 1 and 32
  ),
  constraint circle_bots_token_hash_format check (
    token_hash is null or token_hash ~ '^[0-9a-f]{64}$'
  )
);

create index if not exists circle_bots_circle_idx on public.circle_bots (circle_id);
create index if not exists circle_bots_token_idx on public.circle_bots (token_hash)
  where token_hash is not null;

create table if not exists public.bot_commands (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.circle_bots(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  description text not null,
  created_at timestamptz not null default now(),
  constraint bot_commands_name_format check (name ~ '^[a-z0-9_-]{1,32}$'),
  constraint bot_commands_description_length check (
    description = btrim(description) and char_length(description) between 1 and 100
  ),
  constraint bot_commands_circle_name_unique unique (circle_id, name)
);

create index if not exists bot_commands_bot_idx on public.bot_commands (bot_id);

create table if not exists public.bot_interactions (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.circle_bots(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  channel_id uuid not null references public.circle_channels(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  command_name text not null,
  options text not null default '',
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  claimed_at timestamptz,
  responded_at timestamptz,
  response_message_id uuid references public.messages(id) on delete set null,
  constraint bot_interactions_options_length check (char_length(options) <= 2000)
);

create index if not exists bot_interactions_pending_idx
  on public.bot_interactions (bot_id, created_at)
  where responded_at is null;
create index if not exists bot_interactions_user_idx
  on public.bot_interactions (user_id, created_at);

create table if not exists public.bot_rate (
  bot_id uuid primary key references public.circle_bots(id) on delete cascade,
  window_start timestamptz not null,
  count integer not null default 0
);

alter table public.circle_bots enable row level security;
alter table public.bot_commands enable row level security;
alter table public.bot_interactions enable row level security;
alter table public.bot_rate enable row level security;

revoke all on public.circle_bots from anon, authenticated;
revoke all on public.bot_commands from anon, authenticated;
revoke all on public.bot_interactions from anon, authenticated;
revoke all on public.bot_rate from anon, authenticated;

-- The payload of a bot for its circle's managers: everything but the hash.
create or replace function public.circle_bot_payload(bot public.circle_bots)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', bot.id,
    'circle_id', bot.circle_id,
    'user_id', bot.user_id,
    'name', bot.name,
    'avatar_url', p.avatar_url,
    'username', p.username,
    'has_token', bot.token_hash is not null,
    'is_member', exists (
      select 1
      from public.circle_members cm
      where cm.circle_id = bot.circle_id
        and cm.user_id = bot.user_id
    ),
    'role_names', coalesce((
      select jsonb_agg(r.name order by r.position desc)
      from public.circle_member_roles mr
      join public.circle_roles r on r.id = mr.role_id
      where mr.circle_id = bot.circle_id
        and mr.user_id = bot.user_id
    ), '[]'::jsonb),
    'command_count', (
      select count(*) from public.bot_commands bc where bc.bot_id = bot.id
    ),
    'created_by', bot.created_by,
    'creator_name', case
      when bot.created_by is null then null
      else public.circle_member_label(bot.circle_id, bot.created_by)
    end,
    'created_at', bot.created_at,
    'last_used_at', bot.last_used_at
  )
  from public.profiles p
  where p.id = bot.user_id;
$$;

-- The bot, when the caller may manage it; raises otherwise.
create or replace function public.circle_bot_for_management(target_bot_id uuid)
returns public.circle_bots
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select b.* into bot
  from public.circle_bots b
  where b.id = target_bot_id;

  if bot.id is null
    or not public.current_user_has_circle_permission(bot.circle_id, 'manage_circle')
  then
    raise exception 'Bot not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  return bot;
end;
$$;

revoke execute on function public.circle_bot_payload(public.circle_bots) from public, anon, authenticated;
revoke execute on function public.circle_bot_for_management(uuid) from public, anon, authenticated;

create or replace function public.create_circle_bot(
  target_circle_id uuid,
  bot_name text,
  target_role_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := btrim(coalesce(bot_name, ''));
  given_role public.circle_roles%rowtype;
  bot_user_id uuid := gen_random_uuid();
  token text := public.new_webhook_token();
  created public.circle_bots%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can add bots'
      using errcode = '42501';
  end if;

  if char_length(trimmed_name) not between 1 and 32 then
    raise exception 'Bot name must be 1 to 32 characters' using errcode = '22023';
  end if;

  if target_role_id is not null then
    select r.* into given_role
    from public.circle_roles r
    where r.id = target_role_id
      and r.circle_id = target_circle_id
      and not r.is_default;

    if given_role.id is null
      or not public.current_user_has_circle_permission(target_circle_id, 'manage_roles')
      or given_role.position >= public.circle_member_rank(target_circle_id, current_user_id)
    then
      raise exception 'You cannot give this role' using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bots:' || target_circle_id::text, 0));

  if (
    select count(*) from public.circle_bots b where b.circle_id = target_circle_id
  ) >= 10 then
    raise exception 'A circle can have at most 10 bots' using errcode = '54000';
  end if;

  -- An account that cannot sign in: no email, no password, banned.
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    raw_app_meta_data,
    raw_user_meta_data,
    banned_until,
    created_at,
    updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    bot_user_id,
    'authenticated',
    'authenticated',
    jsonb_build_object('provider', 'bot', 'providers', jsonb_build_array('bot')),
    jsonb_build_object('bot', true, 'display_name', trimmed_name),
    'infinity',
    now(),
    now()
  );

  insert into public.profiles (id, username, display_name, is_bot)
  values (
    bot_user_id,
    'bot_' || substr(replace(bot_user_id::text, '-', ''), 1, 12),
    trimmed_name,
    true
  );

  -- Added by a manager, so the circle's rules (202610160021) count as
  -- accepted.
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at)
  values (target_circle_id, bot_user_id, 'member', now());

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, bot_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
  on conflict do nothing;

  if given_role.id is not null then
    insert into public.circle_member_roles (circle_id, user_id, role_id)
    values (target_circle_id, bot_user_id, given_role.id);
    perform public.sync_circle_admin_roles(target_circle_id);
  end if;

  insert into public.circle_bots (circle_id, user_id, name, token_hash, created_by)
  values (
    target_circle_id,
    bot_user_id,
    trimmed_name,
    public.webhook_token_hash(token),
    current_user_id
  )
  returning * into created;

  perform public.write_circle_audit(
    target_circle_id,
    'bot_create',
    'bot',
    created.id,
    created.name,
    jsonb_strip_nulls(jsonb_build_object('role_name', given_role.name))
  );

  return public.circle_bot_payload(created) || jsonb_build_object('token', token);
end;
$$;

create or replace function public.list_circle_bots(target_circle_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can see bots'
      using errcode = '42501';
  end if;

  return query
  select public.circle_bot_payload(b)
  from public.circle_bots b
  where b.circle_id = target_circle_id
  order by b.created_at, b.id;
end;
$$;

create or replace function public.regenerate_bot_token(target_bot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  token text := public.new_webhook_token();
  updated public.circle_bots%rowtype;
begin
  update public.circle_bots b
  set token_hash = public.webhook_token_hash(token)
  where b.id = bot.id
  returning * into updated;

  perform public.write_circle_audit(
    bot.circle_id, 'bot_regenerate', 'bot', bot.id, bot.name, '{}'::jsonb
  );

  return public.circle_bot_payload(updated) || jsonb_build_object('token', token);
end;
$$;

create or replace function public.revoke_bot_token(target_bot_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  updated public.circle_bots%rowtype;
begin
  update public.circle_bots b
  set token_hash = null
  where b.id = bot.id
  returning * into updated;

  perform public.write_circle_audit(
    bot.circle_id, 'bot_revoke', 'bot', bot.id, bot.name, '{}'::jsonb
  );

  return public.circle_bot_payload(updated);
end;
$$;

create or replace function public.delete_circle_bot(target_bot_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  -- Like kick_circle_member: threads first, then channels, then the circle.
  delete from public.conversation_members cm
  using public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where cc.circle_id = bot.circle_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = bot.user_id;

  delete from public.conversation_members cm
  using public.circle_channels cc
  where cc.circle_id = bot.circle_id
    and cm.conversation_id = cc.conversation_id
    and cm.user_id = bot.user_id;

  delete from public.circle_members cm
  where cm.circle_id = bot.circle_id
    and cm.user_id = bot.user_id;

  delete from public.circle_bots b where b.id = bot.id;

  perform public.sync_circle_admin_roles(bot.circle_id);

  perform public.write_circle_audit(
    bot.circle_id, 'bot_delete', 'bot', bot.id, bot.name, '{}'::jsonb
  );
end;
$$;

-- The commands members of a circle can use: those of bots still in it.
create or replace function public.list_circle_bot_commands(target_circle_id uuid)
returns table (
  bot_id uuid,
  bot_user_id uuid,
  bot_name text,
  name text,
  description text
)
language sql
stable
security definer
set search_path = public
as $$
  select b.id, b.user_id, b.name, bc.name, bc.description
  from public.bot_commands bc
  join public.circle_bots b on b.id = bc.bot_id
  join public.circle_members cm
    on cm.circle_id = b.circle_id
    and cm.user_id = b.user_id
  where bc.circle_id = target_circle_id
    and public.is_current_user_circle_member(target_circle_id)
  order by bc.name;
$$;

create or replace function public.invoke_bot_command(
  target_conversation_id uuid,
  command_name text,
  command_options text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  command public.bot_commands%rowtype;
  bot public.circle_bots%rowtype;
  trimmed_options text := btrim(coalesce(command_options, ''));
  created_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = target_conversation_id;

  if channel.id is null then
    raise exception 'Bot commands work in circle channels' using errcode = '22023';
  end if;

  if not public.user_has_conversation_channel_permission(
    target_conversation_id,
    current_user_id,
    'send_messages'
  ) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;

  if char_length(trimmed_options) > 2000 then
    raise exception 'Command options are too long' using errcode = '22023';
  end if;

  select bc.* into command
  from public.bot_commands bc
  where bc.circle_id = channel.circle_id
    and bc.name = lower(btrim(coalesce(command_name, '')));

  select b.* into bot
  from public.circle_bots b
  where b.id = command.bot_id;

  if command.id is null or bot.id is null then
    raise exception 'Unknown command' using errcode = 'P0002';
  end if;

  if not exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = target_conversation_id
        and cm.user_id = bot.user_id
    )
    or not public.circle_channel_has_permission(channel.id, bot.user_id, 'view_channel')
    or not public.circle_channel_has_permission(channel.id, bot.user_id, 'send_messages')
  then
    raise exception 'This bot cannot answer in this channel' using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.bot_interactions bi
    where bi.user_id = current_user_id
      and bi.created_at > now() - interval '1 minute'
  ) >= 10 then
    raise exception 'Too many commands, wait a moment' using errcode = 'BT429';
  end if;

  insert into public.bot_interactions (
    bot_id,
    circle_id,
    channel_id,
    conversation_id,
    command_name,
    options,
    user_id
  )
  values (
    bot.id,
    channel.circle_id,
    channel.id,
    target_conversation_id,
    command.name,
    trimmed_options,
    current_user_id
  )
  returning id into created_id;

  return jsonb_build_object(
    'interaction_id', created_id,
    'bot_name', bot.name,
    'command', command.name
  );
end;
$$;

-- Bot API -----------------------------------------------------------------

-- The bot behind a token, still in its circle; raises 28000 for unknown or
-- revoked tokens and 42501 when the bot was removed from its circle.
create or replace function public.bot_from_token(bot_token text)
returns public.circle_bots
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
begin
  if bot_token is null or bot_token !~ '^[A-Za-z0-9_-]{43}$' then
    raise exception 'Invalid bot token' using errcode = '28000';
  end if;

  select b.* into bot
  from public.circle_bots b
  where b.token_hash = public.webhook_token_hash(bot_token);

  if bot.id is null then
    raise exception 'Invalid bot token' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = bot.circle_id
      and cm.user_id = bot.user_id
  ) then
    raise exception 'The bot is no longer in its circle' using errcode = '42501';
  end if;

  update public.circle_bots b
  set last_used_at = now()
  where b.id = bot.id
    and (b.last_used_at is null or b.last_used_at < now() - interval '1 minute');

  return bot;
end;
$$;

-- Makes auth.uid() the bot for the rest of the transaction, so existing
-- functions check the bot like any member.
create or replace function public.act_as_bot(bot public.circle_bots)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('request.jwt.claim.sub', bot.user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', bot.user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

-- Counts a write against the bot's limit of 60 per minute.
create or replace function public.count_bot_write(bot public.circle_bots)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  written integer;
begin
  insert into public.bot_rate as rate (bot_id, window_start, count)
  values (bot.id, date_trunc('minute', now()), 1)
  on conflict (bot_id) do update
  set
    count = case
      when rate.window_start = excluded.window_start then rate.count + 1
      else 1
    end,
    window_start = excluded.window_start
  returning rate.count into written;

  if written > 60 then
    raise exception 'Bot rate limit: at most 60 writes per minute'
      using errcode = 'BT429';
  end if;
end;
$$;

-- A channel of the bot's circle that the bot can see; raises otherwise.
create or replace function public.bot_visible_channel(
  bot public.circle_bots,
  target_channel_id uuid
)
returns public.circle_channels
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id
    and cc.circle_id = bot.circle_id;

  if channel.id is null
    or not public.circle_channel_has_permission(channel.id, bot.user_id, 'view_channel')
  then
    raise exception 'Channel not found' using errcode = 'P0002';
  end if;

  return channel;
end;
$$;

revoke execute on function public.bot_from_token(text) from public, anon, authenticated;
revoke execute on function public.act_as_bot(public.circle_bots) from public, anon, authenticated;
revoke execute on function public.count_bot_write(public.circle_bots) from public, anon, authenticated;
revoke execute on function public.bot_visible_channel(public.circle_bots, uuid) from public, anon, authenticated;

create or replace function public.bot_api_me(bot_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
begin
  return jsonb_build_object(
    'id', bot.id,
    'user_id', bot.user_id,
    'name', bot.name,
    'circle_id', bot.circle_id,
    'circle_name', (select c.name from public.circles c where c.id = bot.circle_id)
  );
end;
$$;

create or replace function public.bot_api_list_channels(bot_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
begin
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', cc.id,
        'name', cc.name,
        'kind', cc.kind,
        'topic', cc.topic,
        'category_id', cc.category_id,
        'category_name', ccc.name,
        'position', cc.position,
        'can_send', public.circle_channel_has_permission(cc.id, bot.user_id, 'send_messages')
      )
      order by cc.position, cc.created_at
    )
    from public.circle_channels cc
    left join public.circle_channel_categories ccc on ccc.id = cc.category_id
    where cc.circle_id = bot.circle_id
      and public.circle_channel_has_permission(cc.id, bot.user_id, 'view_channel')
  ), '[]'::jsonb);
end;
$$;

create or replace function public.bot_api_list_messages(
  bot_token text,
  target_channel_id uuid,
  max_count integer default 50,
  before_time timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  channel public.circle_channels%rowtype := public.bot_visible_channel(bot, target_channel_id);
begin
  return coalesce((
    select jsonb_agg(item order by created_at desc, id desc)
    from (
      select
        m.id,
        m.created_at,
        jsonb_build_object(
          'id', m.id,
          'channel_id', channel.id,
          'type', m.type,
          'content', case when m.recalled_at is null then m.body else '' end,
          'deleted', m.recalled_at is not null,
          'created_at', m.created_at,
          'edited_at', m.edited_at,
          'reply_to_message_id', m.reply_to_message_id,
          'author', case
            when m.webhook_name is not null then jsonb_build_object(
              'webhook', true,
              'name', m.webhook_name
            )
            else jsonb_build_object(
              'id', p.id,
              'username', p.username,
              'name', public.circle_member_label(bot.circle_id, p.id),
              'is_bot', p.is_bot
            )
          end,
          'interaction', m.interaction
        ) as item
      from public.messages m
      join public.profiles p on p.id = m.sender_id
      where m.conversation_id = channel.conversation_id
        and m.type <> 'system'
        and (before_time is null or m.created_at < before_time)
      order by m.created_at desc, m.id desc
      limit least(greatest(coalesce(max_count, 50), 1), 100)
    ) page
  ), '[]'::jsonb);
end;
$$;

create or replace function public.bot_api_send_message(
  bot_token text,
  target_channel_id uuid,
  content text,
  reply_to_message_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  channel public.circle_channels%rowtype := public.bot_visible_channel(bot, target_channel_id);
  trimmed_content text := btrim(coalesce(content, ''));
  reply public.messages%rowtype;
  preview jsonb;
begin
  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;

  if reply_to_message_id is not null then
    select m.* into reply
    from public.messages m
    where m.id = bot_api_send_message.reply_to_message_id
      and m.conversation_id = channel.conversation_id;

    if reply.id is null then
      raise exception 'Reply message not found in this channel' using errcode = '22023';
    end if;

    preview := jsonb_build_object(
      'message_id', reply.id,
      'sender_name', coalesce(
        reply.webhook_name,
        public.circle_member_label(bot.circle_id, reply.sender_id)
      ),
      'body', case when reply.recalled_at is null then left(reply.body, 200) else '' end,
      'type', reply.type
    );
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  return public.send_text_message(
    channel.conversation_id,
    trimmed_content,
    reply.id,
    preview,
    '[]'::jsonb
  );
end;
$$;

-- Adds the bot's reaction (nothing when it already reacted with it).
create or replace function public.bot_api_add_reaction(
  bot_token text,
  target_message_id uuid,
  emoji text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  message public.messages%rowtype;
  channel_id uuid;
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  channel_id := public.conversation_circle_channel_id(message.conversation_id);

  if message.id is null
    or channel_id is null
    or not exists (
      select 1
      from public.circle_channels cc
      where cc.id = channel_id
        and cc.circle_id = bot.circle_id
    )
    or not public.user_has_conversation_channel_permission(
      message.conversation_id,
      bot.user_id,
      'view_channel'
    )
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.message_reactions r
    where r.message_id = message.id
      and r.user_id = bot.user_id
      and r.emoji = btrim(coalesce(bot_api_add_reaction.emoji, ''))
  ) then
    return;
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);
  perform public.toggle_message_reaction(message.id, bot_api_add_reaction.emoji);
end;
$$;

create or replace function public.bot_api_list_commands(bot_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
begin
  return coalesce((
    select jsonb_agg(
      jsonb_build_object('name', bc.name, 'description', bc.description)
      order by bc.name
    )
    from public.bot_commands bc
    where bc.bot_id = bot.id
  ), '[]'::jsonb);
end;
$$;

-- Replaces the bot's commands with [{name, description}] (at most 25).
create or replace function public.bot_api_set_commands(
  bot_token text,
  commands jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  command jsonb;
begin
  if jsonb_typeof(commands) is distinct from 'array' then
    raise exception 'commands must be an array' using errcode = '22023';
  end if;

  if jsonb_array_length(commands) > 25 then
    raise exception 'A bot can have at most 25 commands' using errcode = '22023';
  end if;

  perform public.count_bot_write(bot);

  delete from public.bot_commands bc where bc.bot_id = bot.id;

  for command in select value from jsonb_array_elements(commands)
  loop
    if jsonb_typeof(command) is distinct from 'object'
      or coalesce(command->>'name', '') !~ '^[a-z0-9_-]{1,32}$'
      or char_length(btrim(coalesce(command->>'description', ''))) not between 1 and 100
    then
      raise exception 'Each command needs a name (a-z, 0-9, _ or -, up to 32) and a description (up to 100)'
        using errcode = '22023';
    end if;

    begin
      insert into public.bot_commands (bot_id, circle_id, name, description)
      values (
        bot.id,
        bot.circle_id,
        command->>'name',
        btrim(command->>'description')
      );
    exception when unique_violation then
      raise exception 'The command /% already exists in this circle', command->>'name'
        using errcode = '23505';
    end;
  end loop;

  return public.bot_api_list_commands(bot_token);
end;
$$;

-- Hands out unanswered interactions (again 30 seconds after a poll).
create or replace function public.bot_api_poll_interactions(
  bot_token text,
  max_count integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  result jsonb;
begin
  with picked as (
    select bi.id
    from public.bot_interactions bi
    where bi.bot_id = bot.id
      and bi.responded_at is null
      and bi.expires_at > now()
      and (bi.claimed_at is null or bi.claimed_at < now() - interval '30 seconds')
    order by bi.created_at
    limit least(greatest(coalesce(max_count, 25), 1), 100)
    for update skip locked
  ),
  claimed as (
    update public.bot_interactions bi
    set claimed_at = now()
    from picked
    where bi.id = picked.id
    returning bi.*
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'command', c.command_name,
      'options', c.options,
      'channel_id', c.channel_id,
      'user', jsonb_build_object(
        'id', c.user_id,
        'username', p.username,
        'name', public.circle_member_label(c.circle_id, c.user_id)
      ),
      'created_at', c.created_at,
      'expires_at', c.expires_at
    )
    order by c.created_at
  ), '[]'::jsonb)
  into result
  from claimed c
  join public.profiles p on p.id = c.user_id;

  return result;
end;
$$;

-- Answers an interaction once, with a message in its channel.
create or replace function public.bot_api_respond_interaction(
  bot_token text,
  target_interaction_id uuid,
  content text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.bot_from_token(bot_token);
  pending public.bot_interactions%rowtype;
  trimmed_content text := btrim(coalesce(content, ''));
  created_message_id uuid;
begin
  select bi.* into pending
  from public.bot_interactions bi
  where bi.id = target_interaction_id
    and bi.bot_id = bot.id
  for update;

  if pending.id is null or pending.expires_at <= now() then
    raise exception 'Interaction not found or expired' using errcode = 'P0002';
  end if;

  if pending.responded_at is not null then
    raise exception 'Interaction already answered' using errcode = '23505';
  end if;

  if char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;

  perform public.count_bot_write(bot);
  perform public.act_as_bot(bot);

  created_message_id := public.send_text_message(
    pending.conversation_id,
    trimmed_content,
    null,
    null,
    '[]'::jsonb
  );

  -- AutoMod refused it quietly (202610160020): the interaction stays open.
  if created_message_id is null then
    return null;
  end if;

  update public.messages m
  set interaction = jsonb_build_object(
    'interaction_id', pending.id,
    'command', pending.command_name,
    'user_id', pending.user_id,
    'user_name', public.circle_member_label(pending.circle_id, pending.user_id)
  )
  where m.id = created_message_id;

  update public.bot_interactions bi
  set responded_at = now(), response_message_id = created_message_id
  where bi.id = pending.id;

  return created_message_id;
end;
$$;

-- Same as 202610160029_circle_tags, plus whether each user is a bot.
drop function if exists public.list_profile_badges(uuid[]);

create or replace function public.list_profile_badges(user_ids uuid[])
returns table (
  user_id uuid,
  tag text,
  badge text,
  circle_id uuid,
  circle_name text,
  is_bot boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if coalesce(cardinality(user_ids), 0) > 200 then
    raise exception 'At most 200 users at a time' using errcode = '54000';
  end if;

  return query
  select p.id, c.tag, c.tag_badge, c.id, c.name, p.is_bot
  from public.profiles p
  left join public.circles c
    on c.id = p.display_circle_tag_id
    and c.tag is not null
  where p.id = any(user_ids);
end;
$$;

do $$
declare
  fn text;
begin
  foreach fn in array array[
    'bot_api_me(text)',
    'bot_api_list_channels(text)',
    'bot_api_list_messages(text, uuid, integer, timestamptz)',
    'bot_api_send_message(text, uuid, text, uuid)',
    'bot_api_add_reaction(text, uuid, text)',
    'bot_api_list_commands(text)',
    'bot_api_set_commands(text, jsonb)',
    'bot_api_poll_interactions(text, integer)',
    'bot_api_respond_interaction(text, uuid, text)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', fn);
    execute format('grant execute on function public.%s to service_role', fn);
  end loop;
end $$;

grant execute on function public.create_circle_bot(uuid, text, uuid) to authenticated;
grant execute on function public.list_circle_bots(uuid) to authenticated;
grant execute on function public.regenerate_bot_token(uuid) to authenticated;
grant execute on function public.revoke_bot_token(uuid) to authenticated;
grant execute on function public.delete_circle_bot(uuid) to authenticated;
grant execute on function public.list_circle_bot_commands(uuid) to authenticated;
grant execute on function public.invoke_bot_command(uuid, text, text) to authenticated;
grant execute on function public.list_profile_badges(uuid[]) to authenticated;
