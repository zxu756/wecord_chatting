-- Call links: https://wecord.jokebear.fyi/call/<code>.
--
-- A link points at one direct or group chat (its call) or one voice or
-- stage channel. Opening it while signed in joins that call or channel, but
-- only for people who could join it anyway (members of the chat, or circle
-- members who may connect to the channel); everyone else gets a "you don't
-- have access" page. A link therefore grants nothing by itself.
--
-- * Links are scoped to their creator: only the creator lists and revokes
--   them (RLS and revoke_call_link), and up to 50 can be active at once.
-- * They expire after 24 hours, 7 days or never, and can be revoked.
-- * create_call_link and resolve_call_link are the only ways in; the table
--   takes no direct writes.

create table if not exists public.call_links (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  created_by uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  channel_id uuid references public.circle_channels(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  constraint call_links_one_target check (
    (conversation_id is null) <> (channel_id is null)
  )
);

create index if not exists call_links_creator_idx
  on public.call_links (created_by, created_at desc);
create index if not exists call_links_conversation_idx
  on public.call_links (conversation_id)
  where conversation_id is not null;
create index if not exists call_links_channel_idx
  on public.call_links (channel_id)
  where channel_id is not null;

alter table public.call_links enable row level security;

drop policy if exists call_links_select_creator on public.call_links;
create policy call_links_select_creator
  on public.call_links for select
  to authenticated
  using (created_by = auth.uid());

revoke insert, update, delete on public.call_links from anon, authenticated;

-- 12 symbols from a 32 symbol alphabet (so each random byte maps without
-- modulo bias): 60 bits, not guessable.
create or replace function public.generate_call_link_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'abcdefghijkmnpqrstuvwxyz23456789';
  random_bytes bytea := extensions.gen_random_bytes(12);
  generated_code text := '';
begin
  for byte_index in 0..11 loop
    generated_code := generated_code
      || substr(alphabet, (get_byte(random_bytes, byte_index) % 32) + 1, 1);
  end loop;
  return generated_code;
end;
$$;

-- Makes a link to a direct or group chat's call (target_conversation_id) or
-- to a voice channel (target_channel_id). expires_in: 'day', 'week' or
-- 'never'. Returns {code, created_at, expires_at}.
create or replace function public.create_call_link(
  target_conversation_id uuid default null,
  target_channel_id uuid default null,
  expires_in text default 'week'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  expiry timestamptz;
  new_link public.call_links%rowtype;
  attempts integer := 0;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if (target_conversation_id is null) = (target_channel_id is null) then
    raise exception 'Choose a chat or a voice channel' using errcode = '22023';
  end if;

  expiry := case lower(coalesce(expires_in, 'week'))
    when 'day' then now() + interval '24 hours'
    when 'week' then now() + interval '7 days'
    when 'never' then null
    else null
  end;
  if lower(coalesce(expires_in, 'week')) not in ('day', 'week', 'never') then
    raise exception 'Unknown expiry' using errcode = '22023';
  end if;

  if target_conversation_id is not null then
    if not public.can_current_user_call_in_conversation(target_conversation_id) then
      raise exception 'You cannot call in this conversation'
        using errcode = '42501';
    end if;
  elsif public.can_current_user_connect_voice(target_channel_id) is null then
    raise exception 'You cannot connect to this voice channel'
      using errcode = '42501';
  end if;

  if (
    select count(*)
    from public.call_links cl
    where cl.created_by = current_user_id
      and cl.revoked_at is null
      and (cl.expires_at is null or cl.expires_at > now())
  ) >= 50 then
    raise exception 'Too many active call links; revoke some first'
      using errcode = '53400';
  end if;

  loop
    begin
      insert into public.call_links (
        code,
        created_by,
        conversation_id,
        channel_id,
        expires_at
      )
      values (
        public.generate_call_link_code(),
        current_user_id,
        target_conversation_id,
        target_channel_id,
        expiry
      )
      returning * into new_link;
      exit;
    exception when unique_violation then
      attempts := attempts + 1;
      if attempts >= 5 then
        raise;
      end if;
    end;
  end loop;

  return jsonb_build_object(
    'code', new_link.code,
    'created_at', new_link.created_at,
    'expires_at', new_link.expires_at
  );
end;
$$;

-- The caller's links that still work for a chat or a voice channel,
-- newest first.
create or replace function public.list_call_links(
  target_conversation_id uuid default null,
  target_channel_id uuid default null
)
returns table (
  code text,
  created_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select cl.code, cl.created_at, cl.expires_at
  from public.call_links cl
  where auth.uid() is not null
    and cl.created_by = auth.uid()
    and cl.revoked_at is null
    and (cl.expires_at is null or cl.expires_at > now())
    and (
      (target_conversation_id is not null
        and cl.conversation_id = target_conversation_id)
      or (target_channel_id is not null
        and cl.channel_id = target_channel_id)
    )
  order by cl.created_at desc, cl.code;
$$;

-- Stops a link working. Only its creator may.
create or replace function public.revoke_call_link(target_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  found_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.call_links cl
  set revoked_at = now()
  where cl.code = lower(trim(coalesce(target_code, '')))
    and cl.created_by = auth.uid()
    and cl.revoked_at is null
  returning cl.code into found_code;

  if found_code is null then
    raise exception 'Link not found' using errcode = 'P0002';
  end if;
end;
$$;

-- What opening a link does for the caller:
--
--   {status: 'not_found' | 'revoked' | 'expired'}  the link doesn't work;
--   {status: 'no_access'}  it works, but the caller couldn't join anyway
--                          (nothing about the target is revealed);
--   {status: 'ok', kind: 'call', conversation_id, name}
--   {status: 'ok', kind: 'channel', circle_id, channel_id, conversation_id,
--    name}
create or replace function public.resolve_call_link(target_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  link public.call_links%rowtype;
  channel_access jsonb;
  channel_conversation uuid;
  call_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cl.*
  into link
  from public.call_links cl
  where cl.code = lower(trim(coalesce(target_code, '')));

  if link.id is null then
    return jsonb_build_object('status', 'not_found');
  end if;
  if link.revoked_at is not null then
    return jsonb_build_object('status', 'revoked');
  end if;
  if link.expires_at is not null and link.expires_at <= now() then
    return jsonb_build_object('status', 'expired');
  end if;

  if link.conversation_id is not null then
    if not public.can_current_user_call_in_conversation(link.conversation_id) then
      return jsonb_build_object('status', 'no_access');
    end if;

    select coalesce(
      nullif(btrim(c.title), ''),
      (
        select coalesce(nullif(btrim(p.display_name), ''), p.username)
        from public.conversation_members cm
        join public.profiles p on p.id = cm.user_id
        where cm.conversation_id = c.id
          and cm.user_id <> auth.uid()
        order by cm.joined_at
        limit 1
      ),
      'Call'
    )
    into call_name
    from public.conversations c
    where c.id = link.conversation_id;

    return jsonb_build_object(
      'status', 'ok',
      'kind', 'call',
      'conversation_id', link.conversation_id,
      'name', call_name
    );
  end if;

  channel_access := public.can_current_user_connect_voice(link.channel_id);
  if channel_access is null then
    return jsonb_build_object('status', 'no_access');
  end if;

  select cc.conversation_id
  into channel_conversation
  from public.circle_channels cc
  where cc.id = link.channel_id;

  return jsonb_build_object(
    'status', 'ok',
    'kind', 'channel',
    'circle_id', channel_access ->> 'circle_id',
    'channel_id', link.channel_id,
    'conversation_id', channel_conversation,
    'name', channel_access ->> 'channel_name',
    'stage', (channel_access ->> 'kind') = 'stage'
  );
end;
$$;

revoke execute on function public.generate_call_link_code() from public, anon, authenticated;
revoke execute on function public.create_call_link(uuid, uuid, text) from public, anon;
revoke execute on function public.list_call_links(uuid, uuid) from public, anon;
revoke execute on function public.revoke_call_link(text) from public, anon;
revoke execute on function public.resolve_call_link(text) from public, anon;
grant execute on function public.create_call_link(uuid, uuid, text) to authenticated;
grant execute on function public.list_call_links(uuid, uuid) to authenticated;
grant execute on function public.revoke_call_link(text) to authenticated;
grant execute on function public.resolve_call_link(text) to authenticated;
