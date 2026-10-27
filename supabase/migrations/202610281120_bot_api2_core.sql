-- Bot API 2.0 (roadmap I3), part 1 of 5: the foundations.
--
-- The bot API grows from "the channels of the bot's circle" to "every chat the
-- bot is in": a circle's channels and threads, groups it was put in (by the
-- group's owner), and direct chats people started with it. The rule for what
-- a bot may read is one function, bot_conversation_access (202610281100); this
-- part builds on it.
--
-- * bot_api_calls: the last calls a bot made, for the developer page: method,
--   the route as a template (never an id or a text), the status. Kept 7 days
--   and at most about 300 per bot; written by the bot-api function through
--   bot_api_log_call (service role). Closed to clients; managers read it
--   through list_bot_api_calls (202610281150).
-- * bot_visible_conversation: the conversation, when the bot may read it;
--   raises "not found" otherwise (a chat the bot may not read looks like one
--   that is not there).
-- * Rewritten, each the latest definition plus the change named:
--     bot_api_me             (202610160030) + username, description and the two
--                            switches (allow_direct, allow_groups);
--     bot_api_list_channels  (202610160030) + chat_id, the id every new route
--                            takes;
--     bot_edit_own_message   (202610280620) the chat check is
--                            bot_conversation_access, so a bot changes its own
--                            messages in groups and direct chats too; the rest
--                            (components, AutoMod, edit rules) is unchanged;
--     bot_api_add_reaction   (202610160030) the same widening.
--   bot_api_edit_message and the HTTP routes keep their signatures.

create table if not exists public.bot_api_calls (
  id bigint generated always as identity primary key,
  bot_id uuid not null references public.circle_bots(id) on delete cascade,
  at timestamptz not null default now(),
  method text not null,
  route text not null,
  status integer not null,
  constraint bot_api_calls_method check (method ~ '^[A-Z]{3,7}$'),
  constraint bot_api_calls_route_length check (char_length(route) <= 80)
);

create index if not exists bot_api_calls_bot_idx
  on public.bot_api_calls (bot_id, at desc);
create index if not exists bot_api_calls_at_idx
  on public.bot_api_calls (at);

alter table public.bot_api_calls enable row level security;
revoke all on public.bot_api_calls from public, anon, authenticated;

-- Records one call of the bot behind [bot_token], if the token is a working
-- one (an unknown token leaves no trace). The route is the template of the
-- endpoint, such as /chats/{id}/messages.
create or replace function public.bot_api_log_call(
  bot_token text,
  call_method text,
  call_route text,
  call_status integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  found_bot_id uuid;
begin
  if bot_token is null or bot_token !~ '^[A-Za-z0-9_-]{43}$' then
    return;
  end if;

  select b.id into found_bot_id
  from public.circle_bots b
  where b.token_hash = public.webhook_token_hash(bot_token);

  if found_bot_id is null then
    return;
  end if;

  insert into public.bot_api_calls (bot_id, method, route, status)
  values (
    found_bot_id,
    upper(left(coalesce(call_method, 'GET'), 7)),
    left(coalesce(call_route, '/'), 80),
    least(greatest(coalesce(call_status, 0), 0), 599)
  );

  -- Keeps the newest 300 of a bot (checked now and then, not on every call).
  if random() < 0.05 then
    delete from public.bot_api_calls c
    where c.bot_id = found_bot_id
      and c.id in (
        select old_rows.id
        from public.bot_api_calls old_rows
        where old_rows.bot_id = found_bot_id
        order by old_rows.at desc, old_rows.id desc
        offset 300
      );
  end if;
end;
$$;

revoke execute on function public.bot_api_log_call(text, text, text, integer) from public, anon, authenticated;
grant execute on function public.bot_api_log_call(text, text, text, integer) to service_role;

create or replace function public.purge_bot_api_calls()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_api_calls c where c.at < now() - interval '7 days';
end;
$$;

revoke execute on function public.purge_bot_api_calls() from public, anon, authenticated;
grant execute on function public.purge_bot_api_calls() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'wecord-bot-api-calls-purge';
    perform cron.schedule(
      'wecord-bot-api-calls-purge',
      '41 * * * *',
      'select public.purge_bot_api_calls()'
    );
  else
    raise notice 'pg_cron is not available: call purge_bot_api_calls() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the bot API log purge with pg_cron: %', sqlerrm;
end;
$$;

-- The conversation when the bot may read it, otherwise "not found".
create or replace function public.bot_visible_conversation(
  bot public.circle_bots,
  target_conversation_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.bot_conversation_access(bot, target_conversation_id) then
    raise exception 'Chat not found' using errcode = 'P0002';
  end if;
  return target_conversation_id;
end;
$$;

revoke execute on function public.bot_visible_conversation(public.circle_bots, uuid)
  from public, anon, authenticated;

-- ------------------------------------------------------------- rewritten

-- Latest definition: 202610160030, plus username, description and the two
-- switches.
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
    'circle_name', (select c.name from public.circles c where c.id = bot.circle_id),
    'username', (select p.username from public.profiles p where p.id = bot.user_id),
    'description', nullif(bot.description, ''),
    'allow_direct', bot.allow_direct,
    'allow_groups', bot.allow_groups
  );
end;
$$;

-- Latest definition: 202610160030, plus chat_id (the conversation: the id the
-- routes of the bot API 2.0 take).
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
        'chat_id', cc.conversation_id,
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

-- Latest definition: 202610280620. Changes the bot's own message (text and/or
-- components). A null [new_content] leaves the text; [change_components] says
-- the components are to be replaced (null [new_components] then removes
-- them). The place is checked with bot_conversation_access (its circle's
-- channels, groups and direct chats); everything else is as it was. Returns
-- false when AutoMod refused the change quietly.
create or replace function public.bot_edit_own_message(
  bot public.circle_bots,
  target_message_id uuid,
  new_content text,
  change_components boolean,
  new_components jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  message public.messages%rowtype;
  trimmed_content text := btrim(coalesce(new_content, ''));
  cleaned jsonb := case
    when change_components then public.normalize_message_components(new_components)
    else null
  end;
begin
  if new_content is not null and char_length(trimmed_content) not between 1 and 2000 then
    raise exception 'Content must be 1 to 2000 characters' using errcode = '22023';
  end if;
  if new_content is null and not change_components then
    raise exception 'Nothing to change' using errcode = '22023';
  end if;

  select m.* into message
  from public.messages m
  where m.id = target_message_id
  for update;

  if message.id is null
    or message.sender_id <> bot.user_id
    or message.recalled_at is not null
    or message.type <> 'text'
    or not public.bot_conversation_access(bot, message.conversation_id)
  then
    raise exception 'Message not found' using errcode = 'P0002';
  end if;

  if cleaned is not null
    and public.bot_components_automod(message.conversation_id, bot.user_id, cleaned)
  then
    return false;
  end if;

  begin
    update public.messages m
    set
      body = case
        when new_content is not null then trimmed_content
        else m.body
      end,
      edited_at = case
        when new_content is not null and trimmed_content is distinct from m.body then now()
        else m.edited_at
      end,
      components = case
        when change_components then cleaned
        else m.components
      end
    where m.id = message.id;
  exception when sqlstate 'P0001' then
    -- AutoMod blocked the new text (the edit trigger raises).
    if sqlerrm like 'AutoMod blocked%' then
      return false;
    end if;
    raise;
  end;

  return true;
end;
$$;

-- Latest definition: 202610160030. Adds the bot's reaction (nothing when it
-- already reacted with it), in any chat the bot may read.
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
begin
  select m.* into message
  from public.messages m
  where m.id = target_message_id;

  if message.id is null
    or message.recalled_at is not null
    or message.review_state is not null
    or not public.bot_conversation_access(bot, message.conversation_id)
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

revoke execute on function public.bot_edit_own_message(public.circle_bots, uuid, text, boolean, jsonb) from public, anon, authenticated;
