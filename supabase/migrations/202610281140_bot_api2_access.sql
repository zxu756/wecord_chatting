-- Bot API 2.0 (roadmap I3), part 3 of 5: how a bot gets into groups and
-- direct chats.
--
-- * The bot's managers decide whether people may use it outside the circle:
--   set_bot_availability switches allow_direct (people may start a direct chat
--   with it) and allow_groups (a group's owner may add it), and writes a short
--   description. Both start off. Turning one off closes the door at once: the
--   bot reads and writes nothing in those chats and hears nothing from them
--   (bot_conversation_access), though the chats stay where they are.
-- * Direct chats: "private chats are for friends only" is kept for people.
--   get_or_create_direct_conversation (latest definition: 202605190001) is
--   patched in place (pg_get_functiondef) with ONE exception: a person may open
--   a direct chat with a bot that has allow_direct on and a working token,
--   without being its friend (bot_accepts_direct_chat). The caller must be a
--   person (a bot never starts one), and a block still stops it. Nothing else
--   in the function changes.
-- * Groups: only the group's owner adds a bot (add_bot_to_group), knowing the
--   bot reads what is said in the group from then on; at most 5 bots per
--   group. A restricted group (G6) cannot take a bot. The owner removes it
--   again (remove_bot_from_group). Every member can see which bots are in the
--   group (list_group_bots); a bot also shows as a member with the BOT badge.
-- * search_open_bots: signed-in people find the bots that are open to them by
--   name or username (a bot that is closed to both does not show up).

create or replace function public.set_bot_availability(
  target_bot_id uuid,
  bot_description text,
  direct_chats boolean,
  group_chats boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bot public.circle_bots%rowtype := public.circle_bot_for_management(target_bot_id);
  cleaned text := public.components_clean_text(
    to_jsonb(coalesce(bot_description, '')), 'The description', 0, 200
  );
begin
  update public.circle_bots b
  set
    description = cleaned,
    allow_direct = coalesce(direct_chats, false),
    allow_groups = coalesce(group_chats, false)
  where b.id = bot.id;

  perform public.write_circle_audit(
    bot.circle_id,
    'bot_open_update',
    'bot',
    bot.id,
    bot.name,
    jsonb_build_object(
      'direct', coalesce(direct_chats, false),
      'groups', coalesce(group_chats, false)
    )
  );

  return jsonb_build_object(
    'description', cleaned,
    'allow_direct', coalesce(direct_chats, false),
    'allow_groups', coalesce(group_chats, false)
  );
end;
$$;

revoke execute on function public.set_bot_availability(uuid, text, boolean, boolean) from public, anon;
grant execute on function public.set_bot_availability(uuid, text, boolean, boolean) to authenticated;

-- ------------------------------------------------------------- direct chats

-- Whether [caller] (a person) may open a direct chat with [other_user_id]
-- without being friends: it is a bot that is open to direct chats, with a
-- working token and a place in its circle, in a circle that is not suspended.
create or replace function public.bot_accepts_direct_chat(
  caller uuid,
  other_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_bots b
    join public.circle_members m
      on m.circle_id = b.circle_id and m.user_id = b.user_id
    where b.user_id = other_user_id
      and b.allow_direct
      and b.token_hash is not null
      and not public.circle_is_suspended(b.circle_id)
  )
  and not exists (
    select 1 from public.profiles p where p.id = caller and p.is_bot
  );
$$;

revoke execute on function public.bot_accepts_direct_chat(uuid, uuid)
  from public, anon, authenticated;

-- get_or_create_direct_conversation: the friends-only check gets one exception.
do $$
declare
  current_def text;
  patched text;
  anchor constant text := E'  if not exists (\n    select 1\n    from public.friendships';
begin
  select pg_get_functiondef('public.get_or_create_direct_conversation(uuid)'::regprocedure)
  into current_def;

  if (length(current_def) - length(replace(current_def, anchor, '')))
    / length(anchor) <> 1
  then
    raise exception 'get_or_create_direct_conversation is not the definition this patch expects';
  end if;

  patched := replace(
    current_def,
    anchor,
    E'  if not public.bot_accepts_direct_chat(current_user_id, other_user_id)\n    and not exists (\n    select 1\n    from public.friendships'
  );

  if patched = current_def then
    raise exception 'get_or_create_direct_conversation was not patched';
  end if;

  execute patched;
end $$;

-- ------------------------------------------------------------- groups

create or replace function public.add_bot_to_group(
  target_conversation_id uuid,
  target_bot_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  bot public.circle_bots%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = target_conversation_id
      and c.type = 'group'
      and cm.user_id = current_user_id
      and cm.role = 'owner'
  ) then
    raise exception 'Only the owner of a group can add a bot'
      using errcode = '42501';
  end if;

  select b.* into bot
  from public.circle_bots b
  where b.user_id = target_bot_user_id;

  if bot.id is null
    or not bot.allow_groups
    or bot.token_hash is null
    or not exists (
      select 1 from public.circle_members m
      where m.circle_id = bot.circle_id and m.user_id = bot.user_id
    )
    or public.circle_is_suspended(bot.circle_id)
    or public.are_users_blocked(current_user_id, bot.user_id)
  then
    raise exception 'This bot cannot be added to groups' using errcode = '42501';
  end if;

  if public.conversation_restricts_sharing(target_conversation_id) then
    raise exception 'A restricted group cannot take a bot' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = target_conversation_id and cm.user_id = bot.user_id
  ) then
    return;
  end if;

  if (
    select count(*)
    from public.conversation_members cm
    join public.circle_bots other on other.user_id = cm.user_id
    where cm.conversation_id = target_conversation_id
  ) >= 5 then
    raise exception 'A group can have at most 5 bots' using errcode = '54000';
  end if;

  -- Contract guard: role, 'member'
  insert into public.conversation_members (conversation_id, user_id, role)
  values (target_conversation_id, bot.user_id, 'member');
end;
$$;

create or replace function public.remove_bot_from_group(
  target_conversation_id uuid,
  target_bot_user_id uuid
)
returns void
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
    raise exception 'Only the owner of a group can remove a bot'
      using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.circle_bots b where b.user_id = target_bot_user_id
  ) then
    raise exception 'That is not a bot' using errcode = '22023';
  end if;

  -- Its threads first, like removing any member.
  delete from public.conversation_members cm
  using public.conversation_threads ct
  where ct.parent_conversation_id = target_conversation_id
    and cm.conversation_id = ct.conversation_id
    and cm.user_id = target_bot_user_id;

  delete from public.conversation_members cm
  where cm.conversation_id = target_conversation_id
    and cm.user_id = target_bot_user_id;
end;
$$;

-- The bots in a group, for its members.
create or replace function public.list_group_bots(target_conversation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.conversation_id = target_conversation_id
      and cm.user_id = auth.uid()
      and c.type = 'group'
  ) then
    raise exception 'Group not found' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'user_id', b.user_id,
        'name', b.name,
        'username', p.username,
        'avatar_url', p.avatar_url,
        'description', nullif(b.description, '')
      ))
      order by b.name
    )
    from public.conversation_members cm
    join public.circle_bots b on b.user_id = cm.user_id
    join public.profiles p on p.id = b.user_id
    where cm.conversation_id = target_conversation_id
  ), '[]'::jsonb);
end;
$$;

-- Bots that are open to the caller, found by name or username.
create or replace function public.search_open_bots(search_text text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  needle text := lower(btrim(coalesce(search_text, '')));
  pattern text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(needle) < 2 or char_length(needle) > 40 then
    return '[]'::jsonb;
  end if;

  pattern := '%' || replace(replace(replace(needle, '\', '\\'), '%', '\%'), '_', '\_') || '%';

  return coalesce((
    select jsonb_agg(item order by sort_name, sort_id)
    from (
      select
        b.name as sort_name,
        b.id as sort_id,
        jsonb_strip_nulls(jsonb_build_object(
          'user_id', b.user_id,
          'name', b.name,
          'username', p.username,
          'avatar_url', p.avatar_url,
          'description', nullif(b.description, ''),
          'allow_direct', b.allow_direct,
          'allow_groups', b.allow_groups
        )) as item
      from public.circle_bots b
      join public.profiles p on p.id = b.user_id
      where b.token_hash is not null
        and (b.allow_direct or b.allow_groups)
        and not public.circle_is_suspended(b.circle_id)
        and exists (
          select 1 from public.circle_members m
          where m.circle_id = b.circle_id and m.user_id = b.user_id
        )
        and not public.are_users_blocked(auth.uid(), b.user_id)
        and (lower(b.name) like pattern or lower(p.username) like pattern)
      order by b.name, b.id
      limit 20
    ) found
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.add_bot_to_group(uuid, uuid) from public, anon;
revoke execute on function public.remove_bot_from_group(uuid, uuid) from public, anon;
revoke execute on function public.list_group_bots(uuid) from public, anon;
revoke execute on function public.search_open_bots(text) from public, anon;
grant execute on function public.add_bot_to_group(uuid, uuid) to authenticated;
grant execute on function public.remove_bot_from_group(uuid, uuid) to authenticated;
grant execute on function public.list_group_bots(uuid) to authenticated;
grant execute on function public.search_open_bots(text) to authenticated;
