-- Group tabs (roadmap D8), part 2 of 3: reading and changing the tabs.
--
-- * get_conversation_tabs(conversation, include_unavailable) answers
--   {can_manage, tabs: [...]} for a member. Each tab has its kind, its target,
--   its title (the live title of a note, list, form or check-in while it
--   stands, else the stored one), an icon where the target has one, and
--   `available`: false when the target was deleted, the card of a form or
--   check-in was removed or is held for review, or the kind needs a circle
--   that the chat is not part of. The app leaves unavailable tabs out; the
--   manage sheet asks for them (include_unavailable) so they can be removed.
--   `circle_id` comes with every tab of a circle channel (kb opens it).
-- * add_conversation_tab(conversation, kind, target, title): only for whoever
--   may pin messages there (can_current_user_pin_messages: the owner and
--   admins of a group, manage_messages in a channel), in a group or a circle
--   channel, at most 12 tabs, none twice, the target checked (a note, list,
--   form or check-in of THIS conversation; a web address that starts with
--   http:// or https://). An empty title takes the target's own.
-- * update_conversation_tab(tab, title), delete_conversation_tab(tab),
--   reorder_conversation_tabs(conversation, ids): the same people. A circle an
--   admin suspended (K1) counts as no membership, so none of it works there.
-- * conversation_tab_target_ok(conversation, kind, target) is the one check
--   of what a tab may point at; a new kind (target_type 'none') needs no code.

create or replace function public.conversation_tab_target_ok(
  p_conversation_id uuid,
  p_kind text,
  p_target text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  kind_target text;
  target_id uuid;
begin
  select k.target_type into kind_target
  from public.conversation_tab_kinds k
  where k.kind = p_kind;
  if kind_target is null then
    return false;
  end if;

  if kind_target = 'none' then
    if p_target is not null then
      return false;
    end if;
    if p_kind = 'kb' then
      return public.check_in_circle_of(p_conversation_id) is not null;
    end if;
    return true;
  end if;

  if p_target is null then
    return false;
  end if;

  if kind_target = 'url' then
    return char_length(p_target) <= 500
      and p_target ~* '^https?://[^\s/?#]+[^\s]*$';
  end if;

  begin
    target_id := p_target::uuid;
  exception when others then
    return false;
  end;

  return case p_kind
    when 'note' then exists (
      select 1 from public.notes n
      where n.id = target_id
        and n.conversation_id = p_conversation_id
        and n.deleted_at is null
    )
    when 'list' then exists (
      select 1 from public.task_lists l
      where l.id = target_id
        and l.conversation_id = p_conversation_id
        and l.deleted_at is null
    )
    when 'form' then exists (
      select 1 from public.forms f
      where f.id = target_id and f.conversation_id = p_conversation_id
    )
    when 'check_in' then exists (
      select 1 from public.check_in_boards b
      where b.id = target_id and b.conversation_id = p_conversation_id
    )
    else false
  end;
end;
$$;

revoke execute on function public.conversation_tab_target_ok(uuid, text, text)
  from public, anon, authenticated;

-- Whether tabs apply to this conversation: a group or a circle channel.
create or replace function public.conversation_tabs_allowed(p_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id and c.type in ('group', 'channel')
  );
$$;

revoke execute on function public.conversation_tabs_allowed(uuid)
  from public, anon, authenticated;

create or replace function public.get_conversation_tabs(
  target_conversation_id uuid,
  include_unavailable boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  home_circle uuid;
  manage boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  home_circle := public.check_in_circle_of(target_conversation_id);
  manage := public.conversation_tabs_allowed(target_conversation_id)
    and public.can_current_user_pin_messages(target_conversation_id);

  return jsonb_build_object(
    'can_manage', manage,
    'tabs', coalesce((
      select jsonb_agg(q.row_json order by q.sort, q.created_at, q.id)
      from (
        select
          r.id,
          r.sort,
          r.created_at,
          jsonb_build_object(
            'id', r.id,
            'kind', r.kind,
            'target', r.target,
            'title', r.live_title,
            'icon', r.icon,
            'sort', r.sort,
            'available', r.available,
            'closed', r.closed,
            'circle_id', home_circle
          ) as row_json,
          r.available
        from (
          select
            t.id,
            t.kind,
            t.target,
            t.sort,
            t.created_at,
            coalesce(
              nullif(btrim(case t.kind
                when 'note' then n.title
                when 'list' then l.title
                when 'form' then f.title
                when 'check_in' then b.title
              end), ''),
              t.title
            ) as live_title,
            case t.kind
              when 'note' then n.icon
              when 'list' then l.icon
            end as icon,
            case t.kind
              when 'note' then n.id is not null and n.deleted_at is null
              when 'list' then l.id is not null and l.deleted_at is null
              when 'form' then f.id is not null and public.form_card_visible(f.message_id)
              when 'check_in' then b.id is not null and public.check_in_card_visible(b.message_id)
              when 'kb' then home_circle is not null
              else true
            end as available,
            case t.kind
              when 'form' then f.id is not null and public.form_is_closed(f)
              when 'check_in' then b.id is not null and public.check_in_is_closed(b)
              else false
            end as closed
          from public.conversation_tabs t
          left join public.notes n
            on t.kind = 'note' and n.id::text = t.target
            and n.conversation_id = t.conversation_id
          left join public.task_lists l
            on t.kind = 'list' and l.id::text = t.target
            and l.conversation_id = t.conversation_id
          left join public.forms f
            on t.kind = 'form' and f.id::text = t.target
            and f.conversation_id = t.conversation_id
          left join public.check_in_boards b
            on t.kind = 'check_in' and b.id::text = t.target
            and b.conversation_id = t.conversation_id
          where t.conversation_id = target_conversation_id
        ) r
      ) q
      where q.available or include_unavailable
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.add_conversation_tab(
  target_conversation_id uuid,
  tab_kind text,
  tab_target text default null,
  tab_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  clean_target text := nullif(btrim(coalesce(tab_target, '')), '');
  clean_title text := btrim(coalesce(tab_title, ''));
  own_title text;
  new_id uuid;
  next_sort integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if public.is_user_suspended(uid) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  if not public.conversation_tabs_allowed(target_conversation_id) then
    raise exception 'tab_not_allowed' using errcode = '22023';
  end if;
  if not public.can_current_user_pin_messages(target_conversation_id) then
    raise exception 'Only admins can change the tabs' using errcode = '42501';
  end if;
  if not public.conversation_tab_target_ok(target_conversation_id, tab_kind, clean_target) then
    raise exception 'tab_target_invalid' using errcode = '22023';
  end if;

  if clean_title = '' then
    own_title := case tab_kind
      when 'note' then (select nullif(btrim(n.title), '') from public.notes n where n.id = clean_target::uuid)
      when 'list' then (select nullif(btrim(l.title), '') from public.task_lists l where l.id = clean_target::uuid)
      when 'form' then (select f.title from public.forms f where f.id = clean_target::uuid)
      when 'check_in' then (select b.title from public.check_in_boards b where b.id = clean_target::uuid)
    end;
    clean_title := coalesce(own_title, '');
  end if;
  clean_title := left(clean_title, 40);
  if char_length(clean_title) not between 1 and 40 then
    raise exception 'tab_title_invalid' using errcode = '22023';
  end if;

  if (
    select count(*) from public.conversation_tabs t
    where t.conversation_id = target_conversation_id
  ) >= 12 then
    raise exception 'tab_limit' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.conversation_tabs t
    where t.conversation_id = target_conversation_id
      and t.kind = tab_kind
      and coalesce(t.target, '') = coalesce(clean_target, '')
  ) then
    raise exception 'tab_exists' using errcode = 'P0001';
  end if;

  select coalesce(max(t.sort), -1) + 1 into next_sort
  from public.conversation_tabs t
  where t.conversation_id = target_conversation_id;

  insert into public.conversation_tabs (
    conversation_id, kind, target, title, sort, created_by
  )
  values (
    target_conversation_id, tab_kind, clean_target, clean_title, next_sort, uid
  )
  returning id into new_id;

  return jsonb_build_object('id', new_id);
end;
$$;

create or replace function public.update_conversation_tab(
  target_tab_id uuid,
  tab_title text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.conversation_tabs%rowtype;
  clean_title text := btrim(coalesce(tab_title, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into t from public.conversation_tabs where id = target_tab_id;
  if t.id is null or not public.is_current_user_conversation_member(t.conversation_id) then
    raise exception 'Tab not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_pin_messages(t.conversation_id) then
    raise exception 'Only admins can change the tabs' using errcode = '42501';
  end if;
  if char_length(clean_title) not between 1 and 40 then
    raise exception 'tab_title_invalid' using errcode = '22023';
  end if;
  update public.conversation_tabs set title = clean_title where id = t.id;
end;
$$;

create or replace function public.delete_conversation_tab(target_tab_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.conversation_tabs%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into t from public.conversation_tabs where id = target_tab_id;
  if t.id is null or not public.is_current_user_conversation_member(t.conversation_id) then
    raise exception 'Tab not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_pin_messages(t.conversation_id) then
    raise exception 'Only admins can change the tabs' using errcode = '42501';
  end if;
  delete from public.conversation_tabs where id = t.id;
end;
$$;

-- Puts the tabs in the order of [tab_ids]; tabs not listed follow in their
-- old order.
create or replace function public.reorder_conversation_tabs(
  target_conversation_id uuid,
  tab_ids uuid[]
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
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_pin_messages(target_conversation_id) then
    raise exception 'Only admins can change the tabs' using errcode = '42501';
  end if;

  update public.conversation_tabs t
  set sort = ordered.pos
  from (
    select
      t2.id,
      (row_number() over (
        order by coalesce(array_position(tab_ids, t2.id), 1000000), t2.sort, t2.created_at, t2.id
      ) - 1)::integer as pos
    from public.conversation_tabs t2
    where t2.conversation_id = target_conversation_id
  ) ordered
  where t.id = ordered.id;
end;
$$;

revoke execute on function public.get_conversation_tabs(uuid, boolean) from public, anon;
revoke execute on function public.add_conversation_tab(uuid, text, text, text) from public, anon;
revoke execute on function public.update_conversation_tab(uuid, text) from public, anon;
revoke execute on function public.delete_conversation_tab(uuid) from public, anon;
revoke execute on function public.reorder_conversation_tabs(uuid, uuid[]) from public, anon;

grant execute on function public.get_conversation_tabs(uuid, boolean) to authenticated;
grant execute on function public.add_conversation_tab(uuid, text, text, text) to authenticated;
grant execute on function public.update_conversation_tab(uuid, text) to authenticated;
grant execute on function public.delete_conversation_tab(uuid) to authenticated;
grant execute on function public.reorder_conversation_tabs(uuid, uuid[]) to authenticated;
