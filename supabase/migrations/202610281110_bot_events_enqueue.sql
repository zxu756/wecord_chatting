-- Event subscriptions, a bot's outgoing webhook (roadmap I2), part 2 of 4:
-- noticing events, what goes into each, and the queue the bot-events function
-- works through. The rule for what a bot may be told is in
-- 202610281100_bot_events_schema.sql; this is where it is applied.
--
-- * Triggers on messages (created, edited, deleted, released by the AI guard),
--   message_mentions, message_reactions, circle_members, conversation_members
--   (groups only) and bot_interactions queue an event for each bot that
--   subscribed to it and may read the place it happened
--   (bot_event_recipients -> bot_conversation_access). Nothing is queued for
--   the bot's own doing, for a message under review, deleted or expired, or
--   for a person who blocked the bot. Each trigger returns at once when no
--   bot subscribed.
-- * The words of a message are left out (content_withheld) in a restricted
--   chat (G6), a chat a member locked (G2), a disappearing message and a
--   view-once picture; other kinds of message (poll, location, contact card,
--   ...) are named by type only. Files give their name, size and kind, never a
--   link.
-- * A bot gets at most 300 events a minute and has at most 1000 waiting; more
--   are counted (dropped_count) and not queued.
-- * The queue: claim_bot_events hands the function up to 20 due deliveries as
--   a 30 second lease and checks again that the bot may still read the place;
--   finish_bot_event records the result. A failed send is tried again after 5
--   seconds, 30 seconds, 2 minutes, 10 minutes and an hour (six tries in all),
--   then it is failed; 20 lost in a row pause the subscription (saving it again
--   turns it on). A subscription whose owner stopped managing the circle is
--   paused when something is due.
-- * A separate pg_cron job wakes the function every minute when something is
--   due, and an hourly one removes deliveries older than 7 days.
--   run_later_dispatch is not touched; the function is woken the way I1 wakes
--   bot-callbacks (Vault secrets, DISPATCH_SECRET as the bearer token).

create index if not exists bot_event_deliveries_pending_idx
  on public.bot_event_deliveries (bot_id)
  where state in ('queued', 'sending');

-- ------------------------------------------------------------ small pieces

-- A person as a bot sees them: what anyone signed in can read of a profile.
create or replace function public.bot_event_person(
  target_circle_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'name', case
      when target_circle_id is not null
        then public.circle_member_label(target_circle_id, p.id)
      else coalesce(nullif(btrim(p.display_name), ''), p.username)
    end,
    'is_bot', p.is_bot
  )
  from public.profiles p
  where p.id = target_user_id;
$$;

-- Where something happened: the chat, as {id, kind, name, circle_id, ...}.
-- kind is channel, thread, group or direct.
create or replace function public.bot_event_chat(target_conversation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', c.id,
    'kind', case
      when ct.id is not null then 'thread'
      when cc.id is not null then 'channel'
      else c.type
    end,
    'name', case
      when ct.id is not null then nullif(btrim(ct.title), '')
      when cc.id is not null then cc.name
      else nullif(btrim(c.title), '')
    end,
    'circle_id', cc.circle_id,
    'channel_id', cc.id,
    'channel_kind', cc.kind,
    'parent_id', ct.parent_conversation_id
  ))
  from public.conversations c
  left join public.conversation_threads ct on ct.conversation_id = c.id
  left join public.circle_channels cc
    on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)
  where c.id = target_conversation_id;
$$;

create or replace function public.bot_event_circle_of(target_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select cc.circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(target_conversation_id);
$$;

-- Why the words of a message are not sent, or null when they may be.
create or replace function public.bot_event_withheld_reason(
  target_conversation_id uuid,
  message public.messages
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  parent_id uuid := coalesce((
    select ct.parent_conversation_id
    from public.conversation_threads ct
    where ct.conversation_id = target_conversation_id
  ), target_conversation_id);
begin
  if public.conversation_restricts_sharing(target_conversation_id) then
    return 'restricted';
  end if;

  -- A member locked the chat (G2): what is said in it is not read by programs.
  if exists (
    select 1
    from public.user_notification_settings s
    join public.conversation_members cm
      on cm.conversation_id = parent_id
      and cm.user_id = s.user_id
    where parent_id = any (s.locked_conversation_ids)
  ) then
    return 'locked';
  end if;

  if message.expires_at is not null then
    return 'disappearing';
  end if;

  if message.attachment->>'view_once' = 'true' then
    return 'view_once';
  end if;

  return null;
end;
$$;

-- A message as a bot is told about it.
create or replace function public.bot_event_message_json(
  message public.messages,
  target_circle_id uuid,
  withheld text
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', message.id,
    'type', message.type,
    'content', case
      when withheld is null
        and message.type in ('text', 'image', 'file', 'video')
        and message.body <> ''
        then left(message.body, 4000)
    end,
    'truncated', case
      when withheld is null and char_length(message.body) > 4000 then true
    end,
    'content_withheld', withheld,
    'reply_to_message_id', message.reply_to_message_id,
    'created_at', message.created_at,
    'edited_at', message.edited_at,
    'author', case
      when message.webhook_name is not null
        then jsonb_build_object('webhook', true, 'name', left(message.webhook_name, 80))
      else coalesce(
        public.bot_event_person(target_circle_id, message.sender_id),
        jsonb_build_object('id', message.sender_id)
      )
    end,
    'attachment', case
      when withheld is null
        and message.type in ('image', 'file', 'video', 'voice')
        and jsonb_typeof(message.attachment) = 'object'
        then jsonb_strip_nulls(jsonb_build_object(
          'kind', message.attachment->>'kind',
          'name', left(message.attachment->>'name', 200),
          'size', message.attachment->'size',
          'mime_type', left(message.attachment->>'mime_type', 100)
        ))
    end
  ));
$$;

revoke execute on function public.bot_event_person(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.bot_event_chat(uuid) from public, anon, authenticated;
revoke execute on function public.bot_event_circle_of(uuid) from public, anon, authenticated;
revoke execute on function public.bot_event_withheld_reason(uuid, public.messages) from public, anon, authenticated;
revoke execute on function public.bot_event_message_json(public.messages, uuid, text) from public, anon, authenticated;

-- The bots that subscribed to [event_name] and may read the conversation.
create or replace function public.bot_event_recipients(
  event_name text,
  target_conversation_id uuid
)
returns setof public.circle_bots
language sql
stable
security definer
set search_path = public
as $$
  select b.*
  from public.bot_event_subscriptions s
  join public.circle_bots b on b.id = s.bot_id
  join public.conversation_members cm
    on cm.conversation_id = target_conversation_id
    and cm.user_id = b.user_id
  where s.enabled
    and event_name = any (s.events)
    and b.token_hash is not null
    and public.bot_conversation_access(b, target_conversation_id);
$$;

revoke execute on function public.bot_event_recipients(text, uuid) from public, anon, authenticated;

-- Wakes the bot-events function the way I1 wakes bot-callbacks: with the Vault
-- secrets wecord_functions_url and wecord_dispatch_secret, the secret as the
-- bearer token. Quietly does nothing where Vault or pg_net, or a secret, is
-- missing.
create or replace function public.wake_bot_events()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
begin
  select d.decrypted_secret
  into functions_url
  from vault.decrypted_secrets d
  where d.name = 'wecord_functions_url';
  select d.decrypted_secret
  into dispatch_secret
  from vault.decrypted_secrets d
  where d.name = 'wecord_dispatch_secret';

  if functions_url is null or dispatch_secret is null then
    return;
  end if;

  perform net.http_post(
    url := rtrim(functions_url, '/') || '/bot-events',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || dispatch_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  null;
end;
$$;

revoke execute on function public.wake_bot_events() from public, anon, authenticated;
grant execute on function public.wake_bot_events() to service_role;

-- Queues one event for one bot, within its limits. True when queued.
create or replace function public.bot_event_enqueue(
  target_bot_id uuid,
  event_name text,
  target_conversation_id uuid,
  actor uuid,
  data jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  counted integer;
begin
  update public.bot_event_subscriptions s
  set
    window_count = case
      when s.window_start is not null and s.window_start > now() - interval '1 minute'
        then s.window_count + 1
      else 1
    end,
    window_start = case
      when s.window_start is not null and s.window_start > now() - interval '1 minute'
        then s.window_start
      else now()
    end
  where s.bot_id = target_bot_id
    and s.enabled
  returning s.window_count into counted;

  if counted is null then
    return false;
  end if;

  if counted > 300 or (
    select count(*)
    from public.bot_event_deliveries d
    where d.bot_id = target_bot_id
      and d.state in ('queued', 'sending')
  ) >= 1000 then
    update public.bot_event_subscriptions s
    set dropped_count = s.dropped_count + 1
    where s.bot_id = target_bot_id;
    return false;
  end if;

  insert into public.bot_event_deliveries (
    bot_id, event, conversation_id, actor_id, payload
  )
  values (target_bot_id, event_name, target_conversation_id, actor, data);

  perform public.wake_bot_events();
  return true;
end;
$$;

revoke execute on function public.bot_event_enqueue(uuid, text, uuid, uuid, jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------- the triggers

-- A new message (or one the AI guard just released).
create or replace function public.bot_event_send_message_created(message public.messages)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  circle_id uuid;
  chat jsonb;
  withheld text;
  data jsonb;
begin
  if not exists (
    select 1
    from public.bot_event_subscriptions s
    where s.enabled and 'message.created' = any (s.events)
  ) then
    return;
  end if;

  circle_id := public.bot_event_circle_of(message.conversation_id);

  for bot in
    select * from public.bot_event_recipients('message.created', message.conversation_id)
  loop
    if bot.user_id = message.sender_id
      or public.are_users_blocked(message.sender_id, bot.user_id)
    then
      continue;
    end if;
    if data is null then
      chat := public.bot_event_chat(message.conversation_id);
      withheld := public.bot_event_withheld_reason(message.conversation_id, message);
      data := jsonb_build_object(
        'chat', chat,
        'message', public.bot_event_message_json(message, circle_id, withheld)
      );
    end if;
    perform public.bot_event_enqueue(
      bot.id, 'message.created', message.conversation_id, message.sender_id, data
    );
  end loop;
end;
$$;

create or replace function public.messages_bot_events_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.bot_event_send_message_created(new);
  return null;
end;
$$;

-- An edit, a delete, or a message released after review.
create or replace function public.messages_bot_events_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  circle_id uuid;
  withheld text;
  data jsonb;
begin
  if new.type = 'system' then
    return null;
  end if;

  -- Deleted (recalled): only that it happened.
  if old.recalled_at is null and new.recalled_at is not null then
    if old.review_state is not null then
      return null;
    end if;
    for bot in
      select * from public.bot_event_recipients('message.deleted', new.conversation_id)
    loop
      if bot.user_id = new.sender_id
        or public.are_users_blocked(new.sender_id, bot.user_id)
      then
        continue;
      end if;
      perform public.bot_event_enqueue(
        bot.id,
        'message.deleted',
        new.conversation_id,
        new.sender_id,
        jsonb_build_object(
          'chat', public.bot_event_chat(new.conversation_id),
          'message', jsonb_build_object('id', new.id, 'deleted_at', new.recalled_at)
        )
      );
    end loop;
    return null;
  end if;

  if new.recalled_at is not null then
    return null;
  end if;

  -- Released by the AI guard: it is a new message to everyone else.
  if old.review_state is not null and new.review_state is null then
    perform public.bot_event_send_message_created(new);
    return null;
  end if;

  if new.review_state is null
    and new.body is distinct from old.body
    and new.edited_at is distinct from old.edited_at
  then
    circle_id := public.bot_event_circle_of(new.conversation_id);
    for bot in
      select * from public.bot_event_recipients('message.updated', new.conversation_id)
    loop
      if bot.user_id = new.sender_id
        or public.are_users_blocked(new.sender_id, bot.user_id)
      then
        continue;
      end if;
      if data is null then
        withheld := public.bot_event_withheld_reason(new.conversation_id, new);
        data := jsonb_build_object(
          'chat', public.bot_event_chat(new.conversation_id),
          'message', public.bot_event_message_json(new, circle_id, withheld)
        );
      end if;
      perform public.bot_event_enqueue(
        bot.id, 'message.updated', new.conversation_id, new.sender_id, data
      );
    end loop;
  end if;
  return null;
end;
$$;

-- A message that mentions a bot.
create or replace function public.message_mentions_bot_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  message public.messages%rowtype;
  withheld text;
begin
  if not exists (
    select 1
    from public.circle_bots b
    where b.user_id = new.user_id
  ) then
    return null;
  end if;

  select m.* into message
  from public.messages m
  where m.id = new.message_id;

  if message.id is null
    or message.review_state is not null
    or message.recalled_at is not null
    or message.type = 'system'
  then
    return null;
  end if;

  for bot in
    select *
    from public.bot_event_recipients('message.mentioned', new.conversation_id) r
    where r.user_id = new.user_id
  loop
    if bot.user_id = message.sender_id
      or public.are_users_blocked(message.sender_id, bot.user_id)
    then
      continue;
    end if;
    withheld := public.bot_event_withheld_reason(new.conversation_id, message);
    perform public.bot_event_enqueue(
      bot.id,
      'message.mentioned',
      new.conversation_id,
      message.sender_id,
      jsonb_build_object(
        'chat', public.bot_event_chat(new.conversation_id),
        'message', public.bot_event_message_json(
          message, public.bot_event_circle_of(new.conversation_id), withheld
        ),
        'mention', jsonb_build_object('kind', new.kind)
      )
    );
  end loop;
  return null;
end;
$$;

-- A reaction: who, to which message, with what. Never the message's words.
create or replace function public.message_reactions_bot_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  message public.messages%rowtype;
begin
  if not exists (
    select 1
    from public.bot_event_subscriptions s
    where s.enabled and 'reaction.added' = any (s.events)
  ) then
    return null;
  end if;

  select m.* into message
  from public.messages m
  where m.id = new.message_id;

  if message.id is null
    or message.review_state is not null
    or message.recalled_at is not null
    or (message.expires_at is not null and message.expires_at <= now())
  then
    return null;
  end if;

  for bot in
    select * from public.bot_event_recipients('reaction.added', message.conversation_id)
  loop
    if bot.user_id = new.user_id
      or public.are_users_blocked(new.user_id, bot.user_id)
    then
      continue;
    end if;
    perform public.bot_event_enqueue(
      bot.id,
      'reaction.added',
      message.conversation_id,
      new.user_id,
      jsonb_build_object(
        'chat', public.bot_event_chat(message.conversation_id),
        'message_id', message.id,
        'emoji', left(new.emoji, 80),
        'user', public.bot_event_person(
          public.bot_event_circle_of(message.conversation_id), new.user_id
        )
      )
    );
  end loop;
  return null;
end;
$$;

-- Someone joined or left a circle, for the bots of that circle.
create or replace function public.circle_members_bot_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  person_circle uuid := case when tg_op = 'DELETE' then old.circle_id else new.circle_id end;
  person_id uuid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  event_name text := case when tg_op = 'DELETE' then 'member.left' else 'member.joined' end;
begin
  if not exists (
    select 1
    from public.bot_event_subscriptions s
    join public.circle_bots b on b.id = s.bot_id
    where s.enabled
      and event_name = any (s.events)
      and b.circle_id = person_circle
  ) then
    return null;
  end if;

  if public.circle_is_suspended(person_circle) then
    return null;
  end if;

  for bot in
    select b.*
    from public.bot_event_subscriptions s
    join public.circle_bots b on b.id = s.bot_id
    where s.enabled
      and event_name = any (s.events)
      and b.circle_id = person_circle
      and b.token_hash is not null
      and b.user_id <> person_id
      and exists (
        select 1
        from public.circle_members m
        where m.circle_id = person_circle and m.user_id = b.user_id
      )
  loop
    if public.are_users_blocked(person_id, bot.user_id) then
      continue;
    end if;
    perform public.bot_event_enqueue(
      bot.id,
      event_name,
      null,
      person_id,
      jsonb_build_object(
        'circle_id', person_circle,
        'user', public.bot_event_person(person_circle, person_id)
      )
    );
  end loop;
  return null;
end;
$$;

-- Someone joined or left a group the bot is in.
create or replace function public.conversation_members_bot_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
  chat_id uuid := case when tg_op = 'DELETE' then old.conversation_id else new.conversation_id end;
  person_id uuid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  event_name text := case when tg_op = 'DELETE' then 'member.left' else 'member.joined' end;
begin
  if not exists (
    select 1
    from public.bot_event_subscriptions s
    where s.enabled and event_name = any (s.events)
  ) then
    return null;
  end if;

  if not exists (
    select 1 from public.conversations c where c.id = chat_id and c.type = 'group'
  ) then
    return null;
  end if;

  for bot in
    select * from public.bot_event_recipients(event_name, chat_id)
  loop
    if bot.user_id = person_id
      or public.are_users_blocked(person_id, bot.user_id)
    then
      continue;
    end if;
    perform public.bot_event_enqueue(
      bot.id,
      event_name,
      chat_id,
      person_id,
      jsonb_build_object(
        'chat', public.bot_event_chat(chat_id),
        'user', public.bot_event_person(null, person_id)
      )
    );
  end loop;
  return null;
end;
$$;

-- A slash command, a press or a form, for a bot without a callback address.
create or replace function public.bot_interactions_bot_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype;
begin
  select b.* into bot
  from public.circle_bots b
  join public.bot_event_subscriptions s on s.bot_id = b.id
  where b.id = new.bot_id
    and s.enabled
    and 'interaction.created' = any (s.events)
    and b.token_hash is not null;

  if bot.id is null or not public.bot_conversation_access(bot, new.conversation_id) then
    return null;
  end if;

  perform public.bot_event_enqueue(
    bot.id,
    'interaction.created',
    new.conversation_id,
    new.user_id,
    jsonb_build_object(
      'chat', public.bot_event_chat(new.conversation_id),
      'interaction', public.bot_interaction_payload(new)
    )
  );
  return null;
end;
$$;

revoke execute on function public.bot_event_send_message_created(public.messages) from public, anon, authenticated;
revoke execute on function public.messages_bot_events_insert() from public, anon, authenticated;
revoke execute on function public.messages_bot_events_update() from public, anon, authenticated;
revoke execute on function public.message_mentions_bot_events() from public, anon, authenticated;
revoke execute on function public.message_reactions_bot_events() from public, anon, authenticated;
revoke execute on function public.circle_members_bot_events() from public, anon, authenticated;
revoke execute on function public.conversation_members_bot_events() from public, anon, authenticated;
revoke execute on function public.bot_interactions_bot_events() from public, anon, authenticated;

drop trigger if exists messages_bot_events_insert on public.messages;
create trigger messages_bot_events_insert
  after insert on public.messages
  for each row
  when (new.type <> 'system' and new.review_state is null and new.recalled_at is null)
  execute function public.messages_bot_events_insert();

drop trigger if exists messages_bot_events_update on public.messages;
create trigger messages_bot_events_update
  after update of body, edited_at, recalled_at, review_state on public.messages
  for each row
  when (
    new.body is distinct from old.body
    or new.recalled_at is distinct from old.recalled_at
    or new.review_state is distinct from old.review_state
  )
  execute function public.messages_bot_events_update();

drop trigger if exists message_mentions_bot_events on public.message_mentions;
create trigger message_mentions_bot_events
  after insert on public.message_mentions
  for each row execute function public.message_mentions_bot_events();

drop trigger if exists message_reactions_bot_events on public.message_reactions;
create trigger message_reactions_bot_events
  after insert on public.message_reactions
  for each row execute function public.message_reactions_bot_events();

drop trigger if exists circle_members_bot_events_insert on public.circle_members;
create trigger circle_members_bot_events_insert
  after insert on public.circle_members
  for each row execute function public.circle_members_bot_events();

drop trigger if exists circle_members_bot_events_delete on public.circle_members;
create trigger circle_members_bot_events_delete
  after delete on public.circle_members
  for each row execute function public.circle_members_bot_events();

drop trigger if exists conversation_members_bot_events_insert on public.conversation_members;
create trigger conversation_members_bot_events_insert
  after insert on public.conversation_members
  for each row execute function public.conversation_members_bot_events();

drop trigger if exists conversation_members_bot_events_delete on public.conversation_members;
create trigger conversation_members_bot_events_delete
  after delete on public.conversation_members
  for each row execute function public.conversation_members_bot_events();

-- Only when the press did not go to the callback (delivery_state 'none').
drop trigger if exists bot_interactions_bot_events on public.bot_interactions;
create trigger bot_interactions_bot_events
  after insert on public.bot_interactions
  for each row
  when (new.delivery_state = 'none')
  execute function public.bot_interactions_bot_events();

-- --------------------------------------------------------------- the queue

-- For the bot-events function (service role): takes up to [max_count] due
-- deliveries with the address and secret of their bot. A claim is a 30 second
-- lease: if the function dies, the delivery is due again after that.
create or replace function public.claim_bot_events(max_count integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  picked uuid;
  due public.bot_event_deliveries%rowtype;
  bot public.circle_bots%rowtype;
  sub public.bot_event_subscriptions%rowtype;
  result jsonb := '[]'::jsonb;
  allowed boolean;
begin
  -- A subscription whose owner no longer manages the circle is paused.
  update public.bot_event_subscriptions s
  set
    enabled = false,
    last_error = 'owner_lost_access',
    updated_at = now()
  from public.circle_bots b
  where b.id = s.bot_id
    and s.enabled
    and (
      s.owner_id is null
      or not public.circle_member_has_permission(b.circle_id, s.owner_id, 'manage_circle')
    )
    and exists (
      select 1
      from public.bot_event_deliveries d
      where d.bot_id = s.bot_id and d.state in ('queued', 'sending')
    );

  -- Nothing to send to: the subscription is off or gone, or the token is.
  update public.bot_event_deliveries d
  set state = 'dropped', last_error = coalesce(d.last_error, 'subscription_off')
  where d.state in ('queued', 'sending')
    and not exists (
      select 1
      from public.bot_event_subscriptions s
      join public.circle_bots b on b.id = s.bot_id
      where s.bot_id = d.bot_id
        and s.enabled
        and b.token_hash is not null
    );

  -- Too old to matter, or tried enough.
  update public.bot_event_deliveries d
  set state = 'dropped', last_error = 'expired'
  where d.state = 'queued'
    and d.created_at < now() - interval '6 hours';
  update public.bot_event_deliveries d
  set state = 'failed', last_error = coalesce(d.last_error, 'no_answer')
  where d.state = 'sending'
    and d.next_attempt_at <= now()
    and d.attempts >= 6;

  for picked in
    select d.id
    from public.bot_event_deliveries d
    where d.state in ('queued', 'sending')
      and d.next_attempt_at <= now()
      and d.attempts < 6
    order by d.next_attempt_at
    limit least(greatest(coalesce(max_count, 20), 1), 50)
    for update of d skip locked
  loop
    select d.* into due from public.bot_event_deliveries d where d.id = picked;
    select b.* into bot from public.circle_bots b where b.id = due.bot_id;
    select s.* into sub from public.bot_event_subscriptions s where s.bot_id = due.bot_id;

    -- The place may have closed to the bot since the event happened.
    allowed := case
      when due.event = 'ping' then true
      when due.conversation_id is not null
        then public.bot_conversation_access(bot, due.conversation_id)
      else
        not public.circle_is_suspended(bot.circle_id)
        and exists (
          select 1
          from public.circle_members m
          where m.circle_id = bot.circle_id and m.user_id = bot.user_id
        )
    end;

    if not allowed then
      update public.bot_event_deliveries d
      set state = 'dropped', last_error = 'no_access'
      where d.id = due.id;
      continue;
    end if;

    update public.bot_event_deliveries d
    set
      state = 'sending',
      attempts = d.attempts + 1,
      next_attempt_at = now() + interval '30 seconds'
    where d.id = due.id;

    result := result || jsonb_build_array(jsonb_build_object(
      'delivery_id', due.id,
      'bot_id', due.bot_id,
      'circle_id', bot.circle_id,
      'event', due.event,
      'attempt', due.attempts + 1,
      'occurred_at', due.created_at,
      'url', sub.url,
      'secret', sub.secret,
      'data', due.payload
    ));
  end loop;

  return result;
end;
$$;

-- The function reports what happened to one send.
create or replace function public.finish_bot_event(
  target_delivery_id uuid,
  delivered boolean,
  http_status integer default null,
  error_text text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  row_state public.bot_event_deliveries%rowtype;
  final_state text;
begin
  select d.* into row_state
  from public.bot_event_deliveries d
  where d.id = target_delivery_id
    and d.state = 'sending'
  for update;

  if row_state.id is null then
    return;
  end if;

  final_state := case
    when delivered then 'delivered'
    when row_state.attempts >= 6 then 'failed'
    else 'queued'
  end;

  update public.bot_event_deliveries d
  set
    state = final_state,
    delivered_at = case when delivered then now() else d.delivered_at end,
    last_status = http_status,
    last_error = case when delivered then null else left(coalesce(error_text, 'failed'), 200) end,
    next_attempt_at = case
      when final_state = 'queued' then now() + case row_state.attempts
        when 1 then interval '5 seconds'
        when 2 then interval '30 seconds'
        when 3 then interval '2 minutes'
        when 4 then interval '10 minutes'
        else interval '1 hour'
      end
      else d.next_attempt_at
    end
  where d.id = row_state.id;

  update public.bot_event_subscriptions s
  set
    last_status = http_status,
    last_error = case when delivered then null else left(coalesce(error_text, 'failed'), 200) end,
    last_success_at = case when delivered then now() else s.last_success_at end,
    last_failure_at = case when delivered then s.last_failure_at else now() end,
    consecutive_failures = case
      when delivered then 0
      when final_state = 'failed' then s.consecutive_failures + 1
      else s.consecutive_failures
    end,
    enabled = case
      when not delivered and final_state = 'failed' and s.consecutive_failures + 1 >= 20 then false
      else s.enabled
    end
  where s.bot_id = row_state.bot_id;
end;
$$;

revoke execute on function public.claim_bot_events(integer) from public, anon, authenticated;
revoke execute on function public.finish_bot_event(uuid, boolean, integer, text) from public, anon, authenticated;
grant execute on function public.claim_bot_events(integer) to service_role;
grant execute on function public.finish_bot_event(uuid, boolean, integer, text) to service_role;

-- Wakes the function when something is due (retries).
create or replace function public.wake_bot_events_if_due()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.bot_event_deliveries d
    where d.state in ('queued', 'sending')
      and d.next_attempt_at <= now()
  ) then
    perform public.wake_bot_events();
  end if;
end;
$$;

-- Deliveries older than 7 days.
create or replace function public.purge_bot_events()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_event_deliveries d
  where d.created_at < now() - interval '7 days';
end;
$$;

revoke execute on function public.wake_bot_events_if_due() from public, anon, authenticated;
revoke execute on function public.purge_bot_events() from public, anon, authenticated;
grant execute on function public.wake_bot_events_if_due() to service_role;
grant execute on function public.purge_bot_events() to service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname in ('wecord-bot-events-retry', 'wecord-bot-events-purge');
    perform cron.schedule(
      'wecord-bot-events-retry',
      '* * * * *',
      'select public.wake_bot_events_if_due()'
    );
    perform cron.schedule(
      'wecord-bot-events-purge',
      '29 * * * *',
      'select public.purge_bot_events()'
    );
  else
    raise notice 'pg_cron is not available: call wake_bot_events_if_due() and purge_bot_events() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the bot event jobs with pg_cron: %', sqlerrm;
end;
$$;

-- --------------------------------------------------- testing and the log

-- A test event, so a manager can see the address answer: queued like any
-- other (signed, checked, retried), at most 5 a minute per bot.
create or replace function public.send_bot_test_event(target_bot_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  sub public.bot_event_subscriptions%rowtype;
  created_id uuid;
begin
  select s.* into sub from public.bot_event_subscriptions s where s.bot_id = bot.id;
  if sub.bot_id is null then
    raise exception 'This bot has no event subscription' using errcode = 'P0002';
  end if;
  if not sub.enabled then
    raise exception 'The subscription is paused: save the address again to turn it on'
      using errcode = '22023';
  end if;

  if (
    select count(*)
    from public.bot_event_deliveries d
    where d.bot_id = bot.id
      and d.event = 'ping'
      and d.created_at > now() - interval '1 minute'
  ) >= 5 then
    raise exception 'Too many tests, wait a moment' using errcode = 'BT429';
  end if;

  insert into public.bot_event_deliveries (bot_id, event, actor_id, payload)
  values (
    bot.id,
    'ping',
    auth.uid(),
    jsonb_build_object(
      'message', 'This is a test event from WeCord.',
      'bot', jsonb_build_object('id', bot.id, 'name', bot.name)
    )
  )
  returning id into created_id;

  perform public.wake_bot_events();
  return created_id;
end;
$$;

-- What happened to the latest deliveries of a bot, for its managers: no
-- payload, only whether it arrived.
create or replace function public.list_bot_event_deliveries(
  target_bot_id uuid,
  max_count integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
begin
  return coalesce((
    select jsonb_agg(item order by created_at desc, id desc)
    from (
      select
        d.id,
        d.created_at,
        jsonb_build_object(
          'id', d.id,
          'event', d.event,
          'state', d.state,
          'attempts', d.attempts,
          'status', d.last_status,
          'error', d.last_error,
          'created_at', d.created_at,
          'delivered_at', d.delivered_at
        ) as item
      from public.bot_event_deliveries d
      where d.bot_id = bot.id
      order by d.created_at desc, d.id desc
      limit least(greatest(coalesce(max_count, 30), 1), 100)
    ) page
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.send_bot_test_event(uuid) from public, anon;
revoke execute on function public.list_bot_event_deliveries(uuid, integer) from public, anon;
grant execute on function public.send_bot_test_event(uuid) to authenticated;
grant execute on function public.list_bot_event_deliveries(uuid, integer) to authenticated;
