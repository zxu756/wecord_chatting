-- Daily digest (F3), part 2 of 5: what the app calls.
--
-- * get_ai_digest_settings(): the person's switch, time, language, the time
--   zone the digest will run in, the chats they follow and the limit.
-- * set_ai_digest_settings(enabled, deliver_at, language): saves them; each
--   argument left null stays as it was.
-- * set_ai_digest_subscription(conversation, subscribed, language): follows
--   or unfollows one chat. Following needs the person to be a member who may
--   read the chat (a circle channel they cannot view is refused) and a group
--   or channel; the 10 chat limit is the trigger's (202610230500) and comes
--   back as SQLSTATE 54000 / "digest_limit". Returns how many chats are
--   followed afterwards.
-- * list_my_ai_digests(): the cards for Notifications: this person's finished
--   digests of the last 7 days, newest first, each with only the chats they
--   still belong to and may still read (leaving a chat or losing a circle
--   channel's permission takes its part out of the card), with the chat's
--   name. A card with nothing left is not listed.
-- * mark_ai_digests_read(ids): the card was seen or dismissed.

-- [t] without its seconds (the digest runs on whole minutes).
create or replace function public.ai_digest_whole_minute(t time)
returns time
language sql
immutable
as $$
  select case
    when t is null then null
    else make_time(extract(hour from t)::integer, extract(minute from t)::integer, 0)
  end;
$$;

create or replace function public.get_ai_digest_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'enabled', coalesce((select s.enabled from public.ai_digest_settings s where s.user_id = me), true),
    'deliver_at', to_char(
      coalesce((select s.deliver_at from public.ai_digest_settings s where s.user_id = me), time '08:00'),
      'HH24:MI'
    ),
    'language', coalesce((select s.language from public.ai_digest_settings s where s.user_id = me), 'en'),
    'time_zone', public.notification_time_zone(me),
    'max_subscriptions', public.ai_digest_max_subscriptions(),
    'subscriptions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conversation_id', sub.conversation_id,
          'title', coalesce(cc.name, c.title),
          'circle_name', ci.name
        )
        order by sub.created_at, sub.conversation_id
      )
      from public.ai_digest_subscriptions sub
      join public.conversations c on c.id = sub.conversation_id
      left join public.circle_channels cc on cc.conversation_id = sub.conversation_id
      left join public.circles ci on ci.id = cc.circle_id
      where sub.user_id = me
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.set_ai_digest_settings(
  p_enabled boolean default null,
  p_deliver_at time default null,
  p_language text default null
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
  if p_language is not null and p_language not in ('en', 'zh') then
    raise exception 'Unknown language' using errcode = '22023';
  end if;

  insert into public.ai_digest_settings (user_id, enabled, deliver_at, language)
  values (
    me,
    coalesce(p_enabled, true),
    public.ai_digest_whole_minute(coalesce(p_deliver_at, time '08:00')),
    coalesce(p_language, 'en')
  )
  on conflict (user_id) do update
  set enabled = coalesce(p_enabled, public.ai_digest_settings.enabled),
      deliver_at = coalesce(
        public.ai_digest_whole_minute(p_deliver_at),
        public.ai_digest_settings.deliver_at
      ),
      language = coalesce(p_language, public.ai_digest_settings.language),
      updated_at = now();
end;
$$;

create or replace function public.set_ai_digest_subscription(
  p_conversation_id uuid,
  p_subscribed boolean,
  p_language text default null
)
returns integer
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
  if p_language is not null and p_language not in ('en', 'zh') then
    raise exception 'Unknown language' using errcode = '22023';
  end if;

  if coalesce(p_subscribed, false) then
    if not public.is_current_user_conversation_member(p_conversation_id)
      or not exists (
        select 1
        from public.current_user_readable_conversation_ids() r(id)
        where r.id = p_conversation_id
      )
    then
      raise exception 'Conversation not found or caller is not a member'
        using errcode = '42501';
    end if;

    -- The first chat followed also makes the settings row (08:00, on).
    insert into public.ai_digest_settings (user_id, language)
    values (me, coalesce(p_language, 'en'))
    on conflict (user_id) do update
    set language = coalesce(p_language, public.ai_digest_settings.language),
        updated_at = now();

    insert into public.ai_digest_subscriptions (user_id, conversation_id)
    values (me, p_conversation_id)
    on conflict (user_id, conversation_id) do nothing;
  else
    delete from public.ai_digest_subscriptions s
    where s.user_id = me and s.conversation_id = p_conversation_id;
  end if;

  return (
    select count(*)::integer
    from public.ai_digest_subscriptions s
    where s.user_id = me
  );
end;
$$;

create or replace function public.list_my_ai_digests()
returns table (
  id uuid,
  local_date date,
  created_at timestamptz,
  read_at timestamptz,
  items jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  return query
  select d.id, d.local_date, coalesce(d.finished_at, d.created_at), d.read_at, kept.items
  from public.ai_digests d
  cross join lateral (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'conversation_id', x.conversation_id,
        'title', coalesce(cc.name, c.title),
        'circle_name', ci.name,
        'summary', x.summary,
        'message_count', x.message_count
      )
      order by x.position
    ), '[]'::jsonb) as items
    from (
      select
        (e.item->>'conversation_id')::uuid as conversation_id,
        e.item->>'summary' as summary,
        coalesce((e.item->>'message_count')::integer, 0) as message_count,
        e.position
      from jsonb_array_elements(d.items) with ordinality e(item, position)
      where e.item->>'conversation_id' ~* '^[0-9a-f-]{36}$'
    ) x
    join public.conversations c on c.id = x.conversation_id
    left join public.circle_channels cc on cc.conversation_id = x.conversation_id
    left join public.circles ci on ci.id = cc.circle_id
    where exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = x.conversation_id and cm.user_id = me
      )
      and x.conversation_id in (
        select r.id from public.current_user_readable_conversation_ids() r(id)
      )
  ) kept
  where d.user_id = me
    and d.status = 'done'
    and d.finished_at > now() - interval '7 days'
    and jsonb_array_length(kept.items) > 0
  order by d.local_date desc, d.id
  limit 14;
end;
$$;

create or replace function public.mark_ai_digests_read(p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  update public.ai_digests d
  set read_at = now()
  where d.user_id = auth.uid()
    and d.id = any(coalesce(p_ids, '{}'::uuid[]))
    and d.read_at is null;
end;
$$;

revoke execute on function public.get_ai_digest_settings() from public, anon;
revoke execute on function public.set_ai_digest_settings(boolean, time, text) from public, anon;
revoke execute on function public.set_ai_digest_subscription(uuid, boolean, text) from public, anon;
revoke execute on function public.list_my_ai_digests() from public, anon;
revoke execute on function public.mark_ai_digests_read(uuid[]) from public, anon;
grant execute on function public.get_ai_digest_settings() to authenticated;
grant execute on function public.set_ai_digest_settings(boolean, time, text) to authenticated;
grant execute on function public.set_ai_digest_subscription(uuid, boolean, text) to authenticated;
grant execute on function public.list_my_ai_digests() to authenticated;
grant execute on function public.mark_ai_digests_read(uuid[]) to authenticated;
