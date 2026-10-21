-- Member titles and honors (roadmap C7), part 2 of 5: titles, and what shows
-- next to a name.
--
--   * set_circle_member_title(circle, member, title): give or clear a title.
--     Same rules as another person's nickname (202610130012): manage_nicknames
--     and a higher rank than theirs (the owner has every permission); and you
--     may give yourself one if you can manage nicknames. Any member can
--     remove their own title, so nobody is stuck with one. A circle that was
--     delisted or suspended (K1) takes no changes. Every change is in the
--     circle's audit log; a title given to somebody else sends them a push
--     (claim_circle_title_pushes, taken by scheduled-dispatch).
--   * list_circle_member_flair(circle): for the members' list and the
--     messages, each member's title and the honors that may be shown to
--     others: the streak milestone they are on and last week's level. Honors
--     are shown only while the circle has them on, the person takes part, the
--     circle has 5 or more people, and last week's board has 5 or more names
--     (a smaller board would say who was active).
--
-- Helpers used by the next migrations live here too.

-- The Monday (UTC) of the last week that is over: the week the board shows.
create or replace function public.honors_week_start()
returns date
language sql
stable
set search_path = public
as $$
  select (date_trunc('week', public.insights_today()::timestamp)::date) - 7;
$$;

-- Whether a circle works out honors at all: they are on, the circle is not
-- taken down, and it has 5 or more people (not counting bots).
create or replace function public.honors_circle_active(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select c.honors_enabled
      and c.disabled_at is null
      and (
        select count(*)
        from public.circle_members cm
        join public.profiles p on p.id = cm.user_id and not p.is_bot
        where cm.circle_id = c.id
      ) >= 5
    from public.circles c
    where c.id = target_circle_id
  ), false);
$$;

-- Whether last week's board for a circle can be shown: 5 or more people on
-- it, who still take part.
create or replace function public.honors_board_published(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.honors_circle_active(target_circle_id)
    and (
      select count(*)
      from public.circle_member_honors h
      join public.circle_members cm
        on cm.circle_id = h.circle_id and cm.user_id = h.user_id
      where h.circle_id = target_circle_id
        and h.kind = 'weekly'
        and h.period_start = public.honors_week_start()
        and not exists (
          select 1 from public.circle_honor_prefs hp
          where hp.circle_id = h.circle_id and hp.user_id = h.user_id
        )
    ) >= 5;
$$;

revoke execute on function public.honors_week_start()
  from public, anon, authenticated;
revoke execute on function public.honors_circle_active(uuid)
  from public, anon, authenticated;
revoke execute on function public.honors_board_published(uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Giving a title
-- ---------------------------------------------------------------------------

create or replace function public.set_circle_member_title(
  target_circle_id uuid,
  target_user_id uuid,
  member_title text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized text := nullif(
    regexp_replace(btrim(coalesce(member_title, '')), '\s+', ' ', 'g'),
    ''
  );
  old_title text;
  target_found boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized is not null and char_length(normalized) > 10 then
    raise exception 'A title is 1 to 10 characters' using errcode = '22023';
  end if;
  -- No angle brackets (they could pass for markup or a time token), and no
  -- control or invisible characters that could disguise a title.
  if normalized is not null and normalized ~ E'[<>\\u0000-\\u001f\\u007f-\\u009f\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u206f\\ufeff]' then
    raise exception 'A title cannot use these characters' using errcode = '22023';
  end if;

  if public.is_user_suspended(current_user_id) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can set titles' using errcode = '42501';
  end if;

  perform public.assert_circle_up(target_circle_id);

  select true, cm.title
  into target_found, old_title
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id
  for update;

  if target_found is null then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  -- Taking your own title off needs no permission; everything else does.
  if not (normalized is null and target_user_id = current_user_id) then
    if not public.current_user_has_circle_permission(
      target_circle_id,
      'manage_nicknames'
    ) then
      raise exception 'Only members who can manage nicknames can set titles'
        using errcode = '42501';
    end if;

    if target_user_id <> current_user_id
      and public.circle_member_rank(target_circle_id, target_user_id)
        >= public.circle_member_rank(target_circle_id, current_user_id)
    then
      raise exception 'Cannot set the title of a member ranked at or above you'
        using errcode = '42501';
    end if;
  end if;

  if old_title is not distinct from normalized then
    return normalized;
  end if;

  update public.circle_members cm
  set title = normalized,
      title_set_at = case when normalized is null then null else now() end
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  perform public.write_circle_audit(
    target_circle_id,
    'member_title_update',
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    jsonb_build_object(
      'title', jsonb_build_object('old', old_title, 'new', normalized)
    )
  );

  -- Somebody else's new title is news to them.
  if normalized is not null and target_user_id <> current_user_id then
    delete from public.circle_title_notices n
    where n.circle_id = target_circle_id
      and n.user_id = target_user_id
      and n.push_claimed_at is null;
    insert into public.circle_title_notices (circle_id, user_id, title)
    values (target_circle_id, target_user_id, normalized);
    perform public.wake_scheduled_dispatch();
  end if;

  return normalized;
end;
$$;

revoke execute on function public.set_circle_member_title(uuid, uuid, text)
  from public, anon;
grant execute on function public.set_circle_member_title(uuid, uuid, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- What shows next to a name
-- ---------------------------------------------------------------------------

-- One row for each member who has a title or an honor to show. streak_level
-- is the highest milestone (7, 30, 100) the running streak has reached;
-- weekly_level is last week's level (1 to 3). Both are null unless they may
-- be shown to others, see the top of this file.
create or replace function public.list_circle_member_flair(target_circle_id uuid)
returns table (
  user_id uuid,
  title text,
  streak_level integer,
  weekly_level integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  published boolean;
  active boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Only circle members can see titles' using errcode = '42501';
  end if;
  -- A suspended circle shows nothing.
  if public.circle_is_suspended(target_circle_id) then
    return;
  end if;

  active := public.honors_circle_active(target_circle_id);
  published := public.honors_board_published(target_circle_id);

  return query
  select
    cm.user_id,
    cm.title,
    case
      when active and not opted.out then (
        select max(m.level)::integer
        from (values (7), (30), (100)) m(level)
        where st.current_streak >= m.level
      )
    end,
    case
      when published and not opted.out then wk.level
    end
  from public.circle_members cm
  left join public.circle_member_honor_stats st
    on st.circle_id = cm.circle_id and st.user_id = cm.user_id
  left join public.circle_member_honors wk
    on wk.circle_id = cm.circle_id
    and wk.user_id = cm.user_id
    and wk.kind = 'weekly'
    and wk.period_start = public.honors_week_start()
  cross join lateral (
    select exists (
      select 1 from public.circle_honor_prefs hp
      where hp.circle_id = cm.circle_id and hp.user_id = cm.user_id
    ) as out
  ) opted
  where cm.circle_id = target_circle_id
    and (
      cm.title is not null
      or (active and not opted.out and st.current_streak >= 7)
      or (published and not opted.out and wk.level is not null)
    );
end;
$$;

revoke execute on function public.list_circle_member_flair(uuid)
  from public, anon;
grant execute on function public.list_circle_member_flair(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- The push for a title
-- ---------------------------------------------------------------------------

-- "<circle> gave you the title X", to the devices of the person, once. One
-- older than 15 minutes when the function gets to it is closed without a
-- push, so a long outage does not end in a burst. Worded in each
-- subscription's language ('en' or 'zh'); names are cleaned of angle
-- brackets, so they cannot pass for a time token.
create or replace function public.claim_circle_title_pushes()
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  update public.circle_title_notices n
  set push_claimed_at = now()
  where n.push_claimed_at is null
    and n.created_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.circle_title_notices n
    set push_claimed_at = now()
    where n.push_claimed_at is null
    returning n.*
  ),
  named as (
    select
      c.id as notice_id,
      c.user_id,
      c.circle_id,
      btrim(replace(replace(c.title, '<', ''), '>', '')) as member_title,
      btrim(replace(replace(ci.name, '<', ''), '>', '')) as circle_name
    from claimed c
    join public.circles ci on ci.id = c.circle_id
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then '你有新头衔了' else 'You have a new title' end,
    case
      when s.language = 'zh' then
        '「' || d.circle_name || '」给你设了头衔「' || d.member_title || '」。'
      else
        d.circle_name || ' gave you the title ' || d.member_title || '.'
    end,
    'title-' || d.notice_id::text,
    '/#/circles/' || d.circle_id::text
  from named d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_circle_title_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_circle_title_pushes() to service_role;
