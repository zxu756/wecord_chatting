-- AI guard 2.0 (roadmap F7), part 1 of 3: what the guard looks at besides text.
--
-- The guard of 202610170090 checks the text of a new member's messages. This
-- adds, without redefining any of its functions:
--
--  * circle_ai_guard_scope: per circle, which more things are checked while
--    the guard is on (managers only, through get_ / set_circle_ai_guard_scope,
--    audited as guard_update): polls (the question and the options), the
--    titles of events, notes and tasks (part 2, 202610260210) and pictures.
--    Polls and titles are on by default (they are text, and cost the same as
--    a message); pictures are off, because they cost more and send the
--    picture to the AI provider.
--  * Pictures are only ever held when the server can really read them.
--    ai_runtime_flags is where the `ai` function writes what it is set up
--    for ("vision": AI_VISION_ENABLED is on); without that flag a picture is
--    sent as usual and never waits for a check, so a missing or unfit vision
--    model never holds anyone's pictures back.
--  * messages_review_scope (BEFORE INSERT on messages, sorts right after
--    messages_review_guard and messages_review_raid): a poll or a picture of
--    a member the guard checks, or of a raid newcomer while the circle is
--    locked down, waits as 'checking', and the guard's own AFTER INSERT
--    trigger, the `ai` function, the Review queue and the sweep take it from
--    there. The rule for who is checked is the guard's (a copy of it lives in
--    ai_guard_applies_to, which the item checks of part 2 share).
--  * ai_guard_message_info: what the function reads after it claimed a
--    message (type, text and attachment), because ai_guard_claim only returns
--    the body.
--  * ai_circle_vision_usage: pictures are counted per circle and day apart
--    from the text checks, with their own, lower limit (the `ai` function's
--    AI_VISION_DAILY_LIMIT_PER_CIRCLE).
--  * message_reviews.unchecked_reason accepts three more reasons: vision_off,
--    vision_unsupported and image_unreadable.
--  * list_message_review_media: the picture or the options of a poll in the
--    Review queue.
--
-- Nothing here changes what the guard does with text.

-- ----------------------------------------------------------------- settings

create table if not exists public.circle_ai_guard_scope (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  check_polls boolean not null default true,
  check_items boolean not null default true,
  check_images boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.circle_ai_guard_scope enable row level security;
revoke all on public.circle_ai_guard_scope from anon, authenticated;

-- What the `ai` function is set up for. Written by it (service role) when it
-- answers a status call or runs a check; read by the triggers.
create table if not exists public.ai_runtime_flags (
  key text primary key check (key ~ '^[a-z_]{1,40}$'),
  enabled boolean not null,
  updated_at timestamptz not null default now()
);

alter table public.ai_runtime_flags enable row level security;
revoke all on public.ai_runtime_flags from anon, authenticated;

create or replace function public.ai_set_runtime_flag(p_key text, p_enabled boolean)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.ai_runtime_flags as f (key, enabled)
  values (p_key, coalesce(p_enabled, false))
  on conflict (key) do update
  set enabled = excluded.enabled, updated_at = now()
  where f.enabled is distinct from excluded.enabled;
$$;

create or replace function public.ai_runtime_flag(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select f.enabled from public.ai_runtime_flags f where f.key = p_key),
    false
  );
$$;

revoke execute on function public.ai_set_runtime_flag(text, boolean) from public, anon, authenticated;
revoke execute on function public.ai_runtime_flag(text) from public, anon, authenticated;
grant execute on function public.ai_set_runtime_flag(text, boolean) to service_role;
grant execute on function public.ai_runtime_flag(text) to service_role;

-- Pictures checked per circle and UTC day.
create table if not exists public.ai_circle_vision_usage (
  circle_id uuid not null references public.circles(id) on delete cascade,
  day date not null default ((now() at time zone 'utc')::date),
  requests integer not null default 0 check (requests >= 0),
  updated_at timestamptz not null default now(),
  primary key (circle_id, day)
);

alter table public.ai_circle_vision_usage enable row level security;
revoke all on public.ai_circle_vision_usage from anon, authenticated;

create or replace function public.ai_consume_circle_vision_request(
  p_circle_id uuid,
  p_limit integer
)
returns table (allowed boolean, used integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  today date := (now() at time zone 'utc')::date;
  new_count integer;
begin
  if p_circle_id is null or p_limit is null or p_limit < 1 then
    raise exception 'A circle and a positive limit are required' using errcode = '22023';
  end if;

  delete from public.ai_circle_vision_usage u
  where u.circle_id = p_circle_id and u.day < today - 30;

  insert into public.ai_circle_vision_usage as u (circle_id, day, requests)
  values (p_circle_id, today, 0)
  on conflict (circle_id, day) do nothing;

  update public.ai_circle_vision_usage u
  set requests = u.requests + 1, updated_at = now()
  where u.circle_id = p_circle_id and u.day = today and u.requests < p_limit
  returning u.requests into new_count;

  if new_count is not null then
    return query select true, new_count;
  else
    return query
      select false, u.requests
      from public.ai_circle_vision_usage u
      where u.circle_id = p_circle_id and u.day = today;
  end if;
end;
$$;

create or replace function public.ai_refund_circle_vision_request(p_circle_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.ai_circle_vision_usage u
  set requests = greatest(u.requests - 1, 0), updated_at = now()
  where u.circle_id = p_circle_id and u.day = (now() at time zone 'utc')::date;
$$;

revoke execute on function public.ai_consume_circle_vision_request(uuid, integer) from public, anon, authenticated;
revoke execute on function public.ai_refund_circle_vision_request(uuid) from public, anon, authenticated;
grant execute on function public.ai_consume_circle_vision_request(uuid, integer) to service_role;
grant execute on function public.ai_refund_circle_vision_request(uuid) to service_role;

-- The reasons a check can end unchecked, plus the three of pictures.
alter table public.message_reviews
  drop constraint if exists message_reviews_unchecked;
alter table public.message_reviews
  add constraint message_reviews_unchecked check (
    unchecked_reason is null
    or unchecked_reason in (
      'not_configured', 'ai_off', 'limit', 'error', 'timeout', 'unavailable',
      'vision_off', 'vision_unsupported', 'image_unreadable'
    )
  );

-- ------------------------------------------------------------ scope settings

create or replace function public.get_circle_ai_guard_scope(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  scope public.circle_ai_guard_scope%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can see the AI guard'
      using errcode = '42501';
  end if;
  if not exists (select 1 from public.circles c where c.id = target_circle_id) then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  select s.* into scope
  from public.circle_ai_guard_scope s
  where s.circle_id = target_circle_id;
  if scope.circle_id is null then
    scope.check_polls := true;
    scope.check_items := true;
    scope.check_images := false;
  end if;

  return jsonb_build_object(
    'check_polls', scope.check_polls,
    'check_items', scope.check_items,
    'check_images', scope.check_images,
    'vision_available', public.ai_runtime_flag('vision')
  );
end;
$$;

create or replace function public.set_circle_ai_guard_scope(
  target_circle_id uuid,
  scope_polls boolean,
  scope_items boolean,
  scope_images boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  circle_name text;
  old_scope jsonb;
  new_scope jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change the AI guard'
      using errcode = '42501';
  end if;
  if scope_polls is null or scope_items is null or scope_images is null then
    raise exception 'Choose valid AI guard settings' using errcode = '22023';
  end if;

  select c.name into circle_name from public.circles c where c.id = target_circle_id for update;
  if circle_name is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  old_scope := public.get_circle_ai_guard_scope(target_circle_id) - 'vision_available';

  insert into public.circle_ai_guard_scope as s (
    circle_id, check_polls, check_items, check_images, updated_by, updated_at
  )
  values (
    target_circle_id, scope_polls, scope_items, scope_images, auth.uid(), now()
  )
  on conflict (circle_id) do update
  set check_polls = excluded.check_polls,
    check_items = excluded.check_items,
    check_images = excluded.check_images,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  new_scope := public.get_circle_ai_guard_scope(target_circle_id);

  if old_scope is distinct from (new_scope - 'vision_available') then
    perform public.write_circle_audit(
      target_circle_id,
      'guard_update',
      'circle',
      target_circle_id,
      circle_name,
      (
        select coalesce(jsonb_object_agg(
          n.key,
          jsonb_build_object('old', old_scope -> n.key, 'new', n.value)
        ), '{}'::jsonb)
        from jsonb_each(new_scope - 'vision_available') n
        where old_scope -> n.key is distinct from n.value
      )
    );
  end if;

  return new_scope;
end;
$$;

revoke execute on function public.get_circle_ai_guard_scope(uuid) from public, anon;
revoke execute on function public.set_circle_ai_guard_scope(uuid, boolean, boolean, boolean) from public, anon;
grant execute on function public.get_circle_ai_guard_scope(uuid) to authenticated;
grant execute on function public.set_circle_ai_guard_scope(uuid, boolean, boolean, boolean) to authenticated;

-- --------------------------------------------------------------- the checks

-- Whether the AI guard checks what [p_user_id] makes in [p_circle_id] right
-- now: the guard and the circle's AI switch are on, the person is a member
-- who is not a bot, a moderator or a manager, and counts as new by the
-- guard's rule (joined recently, or few messages) or arrived in a burst the
-- circle is locked down for (C6). Internal.
create or replace function public.ai_guard_applies_to(
  p_circle_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  guard public.circle_ai_guard%rowtype;
  joined_at timestamptz;
begin
  if p_circle_id is null or p_user_id is null then
    return false;
  end if;

  select g.* into guard
  from public.circle_ai_guard g
  where g.circle_id = p_circle_id and g.enabled;
  if guard.circle_id is null then
    return false;
  end if;

  if not exists (
    select 1 from public.circles c where c.id = p_circle_id and c.ai_enabled
  ) then
    return false;
  end if;

  select cm.created_at into joined_at
  from public.circle_members cm
  where cm.circle_id = p_circle_id and cm.user_id = p_user_id;
  if joined_at is null then
    return false;
  end if;

  if exists (select 1 from public.profiles p where p.id = p_user_id and p.is_bot)
    or public.circle_member_has_permission(p_circle_id, p_user_id, 'manage_messages')
    or public.circle_member_has_permission(p_circle_id, p_user_id, 'manage_circle')
  then
    return false;
  end if;

  if public.circle_raid_newcomer(p_circle_id, p_user_id) then
    return true;
  end if;

  if guard.new_rule = 'joined_days' then
    return joined_at > now() - make_interval(days => guard.joined_days);
  end if;

  return (
    select count(*)
    from (
      select 1
      from public.messages m
      where m.sender_id = p_user_id
        and m.recalled_at is null
        and m.review_state is null
        and m.conversation_id in (
          select cc.conversation_id
          from public.circle_channels cc
          where cc.circle_id = p_circle_id
          union all
          select ct.conversation_id
          from public.conversation_threads ct
          join public.circle_channels cc
            on cc.conversation_id = ct.parent_conversation_id
          where cc.circle_id = p_circle_id
        )
      limit guard.message_count
    ) counted
  ) < guard.message_count;
end;
$$;

revoke execute on function public.ai_guard_applies_to(uuid, uuid) from public, anon, authenticated;
grant execute on function public.ai_guard_applies_to(uuid, uuid) to service_role;

-- BEFORE INSERT on messages: polls and pictures of the people the guard
-- checks wait for the AI like their text does. Sorts after
-- messages_review_guard (which resets review_state) and messages_review_raid.
create or replace function public.messages_review_scope()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  scope public.circle_ai_guard_scope%rowtype;
begin
  if new.review_state is not null
    or new.type not in ('poll', 'image')
    or new.sender_id is null
    or new.webhook_id is not null
    or new.webhook_name is not null
  then
    return new;
  end if;

  -- Someone posing as another sender is refused by the insert policy.
  if auth.uid() is not null and new.sender_id is distinct from auth.uid() then
    return new;
  end if;

  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);
  if channel_circle_id is null then
    return new;
  end if;

  select s.* into scope
  from public.circle_ai_guard_scope s
  where s.circle_id = channel_circle_id;
  if scope.circle_id is null then
    scope.check_polls := true;
    scope.check_images := false;
  end if;

  if new.type = 'poll' then
    if not scope.check_polls or btrim(coalesce(new.body, '')) = '' then
      return new;
    end if;
  else
    -- A picture waits only when the server can read pictures, and never a
    -- view-once one (nobody keeps those to look at).
    if not scope.check_images
      or not public.ai_runtime_flag('vision')
      or new.attachment is null
      or new.attachment ->> 'kind' is distinct from 'image'
      or coalesce(new.attachment ->> 'view_once', 'false') = 'true'
    then
      return new;
    end if;
  end if;

  if public.ai_guard_applies_to(channel_circle_id, new.sender_id) then
    new.review_state := 'checking';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_review_scope() from public, anon, authenticated;

drop trigger if exists messages_review_scope on public.messages;
create trigger messages_review_scope
  before insert on public.messages
  for each row execute function public.messages_review_scope();

-- What the function reads about a message it claimed.
create or replace function public.ai_guard_message_info(p_message_id uuid)
returns table (type text, body text, attachment jsonb)
language sql
stable
security definer
set search_path = public
as $$
  select m.type, m.body, m.attachment
  from public.messages m
  join public.message_reviews r on r.message_id = m.id
  where m.id = p_message_id
    and r.state = 'checking'
    and m.recalled_at is null;
$$;

revoke execute on function public.ai_guard_message_info(uuid) from public, anon, authenticated;
grant execute on function public.ai_guard_message_info(uuid) to service_role;

-- ----------------------------------------------------------- the review queue

-- For the held and flagged polls and pictures of list_message_reviews: the
-- picture's file (the moderator opens it with their own access) or the
-- poll's options. Same visibility as that list.
create or replace function public.list_message_review_media(
  target_circle_id uuid,
  max_results integer default 100
)
returns table (
  message_id uuid,
  type text,
  media jsonb
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

  return query
  select
    r.message_id,
    m.type,
    case m.type
      when 'image' then jsonb_strip_nulls(jsonb_build_object(
        'bucket', m.attachment -> 'bucket',
        'path', m.attachment -> 'path',
        'mime_type', m.attachment -> 'mime_type',
        'width', m.attachment -> 'width',
        'height', m.attachment -> 'height',
        'alt', m.attachment -> 'alt'
      ))
      when 'poll' then jsonb_build_object(
        'options', coalesce((
          select jsonb_agg(o ->> 'text')
          from jsonb_array_elements(
            case when jsonb_typeof(m.attachment -> 'options') = 'array'
              then m.attachment -> 'options' else '[]'::jsonb end
          ) o
        ), '[]'::jsonb)
      )
      else null
    end
  from public.message_reviews r
  join public.messages m on m.id = r.message_id
  where r.circle_id = target_circle_id
    and r.state in ('held', 'flagged')
    and m.type in ('image', 'poll')
    and m.recalled_at is null
    and public.can_current_user_moderate_messages(r.conversation_id)
  order by m.created_at desc, r.message_id desc
  limit least(greatest(coalesce(max_results, 100), 1), 100);
end;
$$;

revoke execute on function public.list_message_review_media(uuid, integer) from public, anon;
grant execute on function public.list_message_review_media(uuid, integer) to authenticated;
