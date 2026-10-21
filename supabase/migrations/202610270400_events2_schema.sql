-- Events 2.0 (roadmap C10), part 1 of 7: what an event can carry, and the
-- tables and helpers the rest builds on.
--
-- Both kinds of event, the ones in group and direct chats (chat_events,
-- 202610170050) and the ones in circles (circle_events, 202610130022), get:
--
--   recurrence     'weekly', 'biweekly' or 'monthly'. Nothing is generated up
--                  front: the next occurrence is made once the current one
--                  has started (events2_sweep, 202610270430), so a series is
--                  one upcoming event at a time, like Discord's.
--   recurrence_tz  the IANA zone of the device that made it. A weekly 18:00 in
--                  Auckland stays 18:00 there across daylight saving: the
--                  next start is worked out on the wall clock of that zone,
--                  from the series anchor, not by adding 7 days to a UTC time.
--   recurrence_anchor  the first start of the series (or the start the
--                  organiser last moved it to). "Monthly on the 31st" is
--                  worked out from it, so February's 28th does not drag every
--                  later month to the 28th.
--   series_id      the occurrences of one series share it.
--   next_spawned_at  set once the next occurrence exists.
--   cover_path     a picture in Storage, always under the conversation's (or
--                  the circle's) own folder.
--   questions      up to 5 questions asked when someone signs up: text,
--                  number or one of 2 to 8 choices, each required or not.
--   capacity       how many may sign up; the rest wait in a waiting list and
--                  move up when a seat frees (events2_promote).
--
-- New tables, all closed to clients (RLS on, no policy; the RPCs read and
-- write them):
--   event_waitlist          who waits, with their answers, in order
--   event_check_in_codes    the codes an organiser shows as a QR (only a hash
--                           is kept); check_in_event reads one
--   event_check_ins         who checked in and when
--   event_photos            pictures people added to an event
--   event_notices           pushes waiting for somebody (a seat opened up)
--
-- The people who answered keep their answers on the sign-up row
-- (chat_event_rsvps.answers, circle_event_rsvps.answers).

-- ---------------------------------------------------------------- columns

alter table public.chat_events
  add column if not exists recurrence text,
  add column if not exists recurrence_tz text,
  add column if not exists recurrence_anchor timestamptz,
  add column if not exists series_id uuid,
  add column if not exists next_spawned_at timestamptz,
  add column if not exists cover_path text,
  add column if not exists questions jsonb not null default '[]'::jsonb,
  add column if not exists capacity integer;

alter table public.circle_events
  add column if not exists recurrence text,
  add column if not exists recurrence_tz text,
  add column if not exists recurrence_anchor timestamptz,
  add column if not exists series_id uuid,
  add column if not exists next_spawned_at timestamptz,
  add column if not exists cover_path text,
  add column if not exists questions jsonb not null default '[]'::jsonb,
  add column if not exists capacity integer;

alter table public.chat_event_rsvps
  add column if not exists answers jsonb not null default '{}'::jsonb;
alter table public.circle_event_rsvps
  add column if not exists answers jsonb not null default '{}'::jsonb;

do $$
declare
  table_name text;
begin
  foreach table_name in array array['chat_events', 'circle_events'] loop
    execute format(
      'alter table public.%I drop constraint if exists %I',
      table_name, table_name || '_events2_check'
    );
    execute format(
      'alter table public.%I add constraint %I check (
         (recurrence is null or recurrence in (''weekly'', ''biweekly'', ''monthly''))
         and (recurrence is null or (recurrence_tz is not null and recurrence_anchor is not null))
         and (capacity is null or capacity between 1 and 10000)
         and (cover_path is null or (char_length(cover_path) between 3 and 300
              and cover_path !~ ''\.\.'' and cover_path !~ ''^/''))
         and jsonb_typeof(questions) = ''array''
         and jsonb_array_length(questions) <= 5
       )',
      table_name, table_name || '_events2_check'
    );
    execute format(
      'create index if not exists %I on public.%I (series_id) where series_id is not null',
      table_name || '_series_idx', table_name
    );
    -- The sweep looks for series whose current occurrence has started.
    execute format(
      'create index if not exists %I on public.%I (starts_at)
         where recurrence is not null and next_spawned_at is null',
      table_name || '_spawn_idx', table_name
    );
  end loop;
end $$;

-- ----------------------------------------------------------------- tables

create table if not exists public.event_waitlist (
  id uuid primary key default gen_random_uuid(),
  chat_event_id uuid references public.chat_events(id) on delete cascade,
  circle_event_id uuid,
  circle_id uuid,
  user_id uuid not null references public.profiles(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  -- The line forms in the order people asked, even within one transaction.
  created_at timestamptz not null default clock_timestamp(),
  constraint event_waitlist_one_event check (
    (chat_event_id is null) <> (circle_event_id is null)
    and (circle_event_id is null) = (circle_id is null)
  ),
  constraint event_waitlist_circle_event_fkey
    foreign key (circle_event_id, circle_id)
    references public.circle_events(id, circle_id) on delete cascade,
  -- Leaving the circle takes you off the list.
  constraint event_waitlist_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id) on delete cascade
);
create unique index if not exists event_waitlist_chat_unique
  on public.event_waitlist (chat_event_id, user_id)
  where chat_event_id is not null;
create unique index if not exists event_waitlist_circle_unique
  on public.event_waitlist (circle_event_id, user_id)
  where circle_event_id is not null;
create index if not exists event_waitlist_order_idx
  on public.event_waitlist (created_at, id);
create index if not exists event_waitlist_user_idx
  on public.event_waitlist (user_id);

create table if not exists public.event_check_in_codes (
  id uuid primary key default gen_random_uuid(),
  chat_event_id uuid references public.chat_events(id) on delete cascade,
  circle_event_id uuid references public.circle_events(id) on delete cascade,
  code_hash text not null unique,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  constraint event_check_in_codes_one_event check (
    (chat_event_id is null) <> (circle_event_id is null)
  )
);
create index if not exists event_check_in_codes_chat_idx
  on public.event_check_in_codes (chat_event_id) where chat_event_id is not null;
create index if not exists event_check_in_codes_circle_idx
  on public.event_check_in_codes (circle_event_id) where circle_event_id is not null;

create table if not exists public.event_check_ins (
  id uuid primary key default gen_random_uuid(),
  chat_event_id uuid references public.chat_events(id) on delete cascade,
  circle_event_id uuid references public.circle_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  constraint event_check_ins_one_event check (
    (chat_event_id is null) <> (circle_event_id is null)
  )
);
create unique index if not exists event_check_ins_chat_unique
  on public.event_check_ins (chat_event_id, user_id) where chat_event_id is not null;
create unique index if not exists event_check_ins_circle_unique
  on public.event_check_ins (circle_event_id, user_id) where circle_event_id is not null;
create index if not exists event_check_ins_user_idx
  on public.event_check_ins (user_id);

create table if not exists public.event_photos (
  id uuid primary key default gen_random_uuid(),
  chat_event_id uuid references public.chat_events(id) on delete cascade,
  circle_event_id uuid references public.circle_events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  bucket text not null,
  path text not null,
  created_at timestamptz not null default now(),
  constraint event_photos_one_event check (
    (chat_event_id is null) <> (circle_event_id is null)
  ),
  constraint event_photos_bucket check (bucket in ('chat-images', 'chat-media')),
  constraint event_photos_path check (
    char_length(path) between 3 and 300 and path !~ '\.\.' and path !~ '^/'
  )
);
create index if not exists event_photos_chat_idx
  on public.event_photos (chat_event_id, created_at) where chat_event_id is not null;
create index if not exists event_photos_circle_idx
  on public.event_photos (circle_event_id, created_at) where circle_event_id is not null;
create index if not exists event_photos_user_idx
  on public.event_photos (user_id);

create table if not exists public.event_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  chat_event_id uuid references public.chat_events(id) on delete cascade,
  circle_event_id uuid references public.circle_events(id) on delete cascade,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz,
  constraint event_notices_kind check (kind in ('waitlist_promoted')),
  constraint event_notices_one_event check (
    (chat_event_id is null) <> (circle_event_id is null)
  )
);
create index if not exists event_notices_unclaimed_idx
  on public.event_notices (created_at) where push_claimed_at is null;
create index if not exists event_notices_user_idx
  on public.event_notices (user_id);

alter table public.event_waitlist enable row level security;
alter table public.event_check_in_codes enable row level security;
alter table public.event_check_ins enable row level security;
alter table public.event_photos enable row level security;
alter table public.event_notices enable row level security;
revoke all on public.event_waitlist from public, anon, authenticated;
revoke all on public.event_check_in_codes from public, anon, authenticated;
revoke all on public.event_check_ins from public, anon, authenticated;
revoke all on public.event_photos from public, anon, authenticated;
revoke all on public.event_notices from public, anon, authenticated;

-- ---------------------------------------------------------------- helpers

-- A zone name the database knows, else UTC.
create or replace function public.events2_valid_zone(p_zone text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select n.name from pg_timezone_names n where n.name = p_zone limit 1),
    'UTC'
  );
$$;

-- The start of the occurrence after [p_after] in a series that began at
-- [p_anchor], worked out on the wall clock of [p_zone]: the same local time
-- every time, whatever daylight saving does to the UTC offset. Occurrence n is
-- anchor + n weeks / 2n weeks / n months (a month shorter than the anchor's
-- day gives its last day, and the next month goes back to the anchor's day).
create or replace function public.events2_next_start(
  p_kind text,
  p_anchor timestamptz,
  p_zone text,
  p_after timestamptz
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  zone text := public.events2_valid_zone(p_zone);
  local_anchor timestamp;
  candidate timestamptz;
  step integer := 1;
begin
  if p_kind not in ('weekly', 'biweekly', 'monthly')
    or p_anchor is null or p_after is null
  then
    return null;
  end if;

  local_anchor := p_anchor at time zone zone;
  -- A series made weekly 30 years ago would be 1560 steps; 5000 is a bound,
  -- not a limit anybody meets.
  while step <= 5000 loop
    candidate := (
      case p_kind
        when 'weekly' then local_anchor + step * interval '7 days'
        when 'biweekly' then local_anchor + step * interval '14 days'
        else local_anchor + step * interval '1 month'
      end
    ) at time zone zone;
    if candidate > p_after then
      return candidate;
    end if;
    step := step + 1;
  end loop;
  return null;
end;
$$;

revoke execute on function public.events2_valid_zone(text) from public, anon, authenticated;
revoke execute on function public.events2_next_start(text, timestamptz, text, timestamptz)
  from public, anon, authenticated;

-- The questions of an event, checked and cleaned: at most 5; each has a label
-- of 1 to 80 characters, a type (text, number or choice), whether it is
-- required, and for a choice 2 to 8 different options of 1 to 40 characters.
create or replace function public.events2_normalize_questions(p_questions jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  result jsonb := '[]'::jsonb;
  item jsonb;
  question_no integer := 0;
  question_id text;
  question_label text;
  question_type text;
  options jsonb;
  option_text text;
  seen_ids text[] := array[]::text[];
  seen_options text[];
begin
  if p_questions is null or jsonb_typeof(p_questions) = 'null' then
    return '[]'::jsonb;
  end if;
  if jsonb_typeof(p_questions) <> 'array' then
    raise exception 'Questions must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(p_questions) > 5 then
    raise exception 'An event can ask at most 5 questions' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(p_questions) loop
    question_no := question_no + 1;
    if jsonb_typeof(item) <> 'object' then
      raise exception 'A question must be an object' using errcode = '22023';
    end if;

    question_label := btrim(regexp_replace(coalesce(item ->> 'label', ''), '\s+', ' ', 'g'));
    if char_length(question_label) not between 1 and 80 then
      raise exception 'A question must be 1 to 80 characters' using errcode = '22023';
    end if;

    question_type := coalesce(item ->> 'type', 'text');
    if question_type not in ('text', 'number', 'choice') then
      raise exception 'A question is text, number or choice' using errcode = '22023';
    end if;

    question_id := coalesce(nullif(btrim(item ->> 'id'), ''), 'q' || question_no);
    if question_id !~ '^[a-z0-9_]{1,20}$' or question_id = any (seen_ids) then
      raise exception 'A question needs its own short id' using errcode = '22023';
    end if;
    seen_ids := seen_ids || question_id;

    options := null;
    if question_type = 'choice' then
      if jsonb_typeof(item -> 'options') is distinct from 'array'
        or jsonb_array_length(item -> 'options') not between 2 and 8
      then
        raise exception 'A choice question needs 2 to 8 options' using errcode = '22023';
      end if;
      options := '[]'::jsonb;
      seen_options := array[]::text[];
      for option_text in
        select btrim(value #>> '{}')
        from jsonb_array_elements(item -> 'options')
      loop
        if option_text is null or char_length(option_text) not between 1 and 40
          or option_text = any (seen_options)
        then
          raise exception 'Options must be different, 1 to 40 characters'
            using errcode = '22023';
        end if;
        seen_options := seen_options || option_text;
        options := options || to_jsonb(option_text);
      end loop;
    end if;

    result := result || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'id', question_id,
      'label', question_label,
      'type', question_type,
      'required', (item -> 'required') = 'true'::jsonb,
      'options', options
    )));
  end loop;
  return result;
end;
$$;

-- What the AI guard reads of an event's questions: their labels.
create or replace function public.events2_question_labels(p_questions jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(q ->> 'label', E'\n'), '')
  from jsonb_array_elements(
    case when jsonb_typeof(p_questions) = 'array' then p_questions else '[]'::jsonb end
  ) q;
$$;

-- A person's answers, checked against the questions and cleaned to
-- {question id: text}. Unknown ids are dropped; text up to 500 characters; a
-- number is a plain decimal; a choice is one of the options. With
-- [p_require], a required question left empty is refused.
create or replace function public.events2_clean_answers(
  p_questions jsonb,
  p_answers jsonb,
  p_require boolean
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  result jsonb := '{}'::jsonb;
  question jsonb;
  given jsonb;
  answer text;
begin
  if p_answers is not null and jsonb_typeof(p_answers) not in ('object', 'null') then
    raise exception 'Answers must be an object' using errcode = '22023';
  end if;
  if jsonb_typeof(p_questions) is distinct from 'array' then
    return result;
  end if;

  for question in select value from jsonb_array_elements(p_questions) loop
    given := case when jsonb_typeof(p_answers) = 'object'
      then p_answers -> (question ->> 'id') end;
    answer := case
      when given is null or jsonb_typeof(given) = 'null' then null
      when jsonb_typeof(given) in ('string', 'number') then btrim(given #>> '{}')
      else null
    end;
    if answer = '' then
      answer := null;
    end if;

    if answer is null then
      if p_require and (question -> 'required') = 'true'::jsonb then
        raise exception 'Please answer the required questions' using errcode = '22023';
      end if;
      continue;
    end if;

    if char_length(answer) > 500 then
      raise exception 'An answer must be at most 500 characters' using errcode = '22023';
    end if;
    if question ->> 'type' = 'number' and answer !~ '^-?[0-9]{1,9}(\.[0-9]{1,4})?$' then
      raise exception 'That answer must be a number' using errcode = '22023';
    end if;
    if question ->> 'type' = 'choice'
      and not (question -> 'options') @> to_jsonb(answer)
    then
      raise exception 'That answer is not one of the choices' using errcode = '22023';
    end if;

    result := result || jsonb_build_object(question ->> 'id', answer);
  end loop;
  return result;
end;
$$;

-- The options of an event after a create or an update: the current values,
-- with each key of [p_options] that is present replaced (a JSON null clears
-- it). Returns {recurrence, recurrence_tz, cover_path, questions, capacity}.
-- [p_scope_id] is the conversation (chat events) or the circle (circle
-- events) whose folder a cover must be in. Recurrence needs a zone: the one
-- sent as `timezone`, else the one the event has, else UTC.
create or replace function public.events2_merge_options(
  p_scope_id uuid,
  p_options jsonb,
  p_recurrence text,
  p_zone text,
  p_cover text,
  p_questions jsonb,
  p_capacity integer
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  new_recurrence text := p_recurrence;
  new_zone text := p_zone;
  new_cover text := p_cover;
  new_questions jsonb := coalesce(p_questions, '[]'::jsonb);
  new_capacity integer := p_capacity;
  option_value jsonb;
begin
  if p_options is not null then
    if jsonb_typeof(p_options) <> 'object' then
      raise exception 'Event options must be an object' using errcode = '22023';
    end if;

    if p_options ? 'recurrence' then
      option_value := p_options -> 'recurrence';
      new_recurrence := case
        when jsonb_typeof(option_value) = 'null' or option_value #>> '{}' in ('', 'none') then null
        else option_value #>> '{}'
      end;
      if new_recurrence is not null
        and new_recurrence not in ('weekly', 'biweekly', 'monthly')
      then
        raise exception 'An event repeats weekly, every two weeks or monthly'
          using errcode = '22023';
      end if;
    end if;

    if p_options ? 'timezone' and jsonb_typeof(p_options -> 'timezone') = 'string' then
      new_zone := public.events2_valid_zone(p_options ->> 'timezone');
    end if;

    if p_options ? 'cover_path' then
      option_value := p_options -> 'cover_path';
      new_cover := case
        when jsonb_typeof(option_value) = 'null' or option_value #>> '{}' = '' then null
        else option_value #>> '{}'
      end;
      if new_cover is not null and (
        char_length(new_cover) not between 3 and 300
        or new_cover ~ '\.\.'
        or new_cover not like p_scope_id::text || '/%'
      ) then
        raise exception 'The cover must be a file in the event''s own folder'
          using errcode = '22023';
      end if;
    end if;

    if p_options ? 'questions' then
      new_questions := public.events2_normalize_questions(p_options -> 'questions');
    end if;

    if p_options ? 'capacity' then
      option_value := p_options -> 'capacity';
      if jsonb_typeof(option_value) = 'null' then
        new_capacity := null;
      elsif jsonb_typeof(option_value) = 'number'
        and (option_value #>> '{}') ~ '^[0-9]{1,5}$'
        and (option_value #>> '{}')::integer between 1 and 10000
      then
        new_capacity := (option_value #>> '{}')::integer;
      else
        raise exception 'Capacity must be between 1 and 10000' using errcode = '22023';
      end if;
    end if;
  end if;

  if new_recurrence is null then
    new_zone := null;
  else
    new_zone := public.events2_valid_zone(coalesce(new_zone, 'UTC'));
  end if;

  return jsonb_build_object(
    'recurrence', new_recurrence,
    'recurrence_tz', new_zone,
    'cover_path', new_cover,
    'questions', new_questions,
    'capacity', new_capacity
  );
end;
$$;

revoke execute on function public.events2_normalize_questions(jsonb) from public, anon, authenticated;
revoke execute on function public.events2_question_labels(jsonb) from public, anon, authenticated;
revoke execute on function public.events2_clean_answers(jsonb, jsonb, boolean)
  from public, anon, authenticated;
revoke execute on function public.events2_merge_options(uuid, jsonb, text, text, text, jsonb, integer)
  from public, anon, authenticated;

-- ------------------------------------------------------------------ K1

-- The takedown rules for circle events (K1). A person an admin suspended
-- writes nothing. A circle that is suspended takes nothing from anybody; a
-- delisted one (or suspended) takes no change from its organisers. [p_manage]
-- is for organisers' changes; signing up, checking in and photos are the
-- members' own and only stop when the circle is suspended.
create or replace function public.events2_assert_circle_open(
  p_circle_id uuid,
  p_manage boolean
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if public.is_user_suspended(auth.uid()) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if public.circle_is_suspended(p_circle_id) then
    raise exception 'This circle was suspended' using errcode = '42501';
  end if;
  if p_manage and exists (
    select 1 from public.circles c
    where c.id = p_circle_id and c.disabled_at is not null
  ) then
    raise exception 'This circle was taken down' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.events2_assert_circle_open(uuid, boolean)
  from public, anon, authenticated;

-- ------------------------------------------------------------- the waiting list

-- How many seats are taken. Chat sign-ups stay when someone leaves the chat,
-- so only people still in it count; a circle drops a sign-up with the member.
create or replace function public.events2_seats_taken(p_kind text, p_event_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_kind = 'chat' then (
      select count(*)::integer
      from public.chat_event_rsvps r
      join public.chat_events e on e.id = r.event_id
      join public.conversation_members cm
        on cm.conversation_id = e.conversation_id and cm.user_id = r.user_id
      where r.event_id = p_event_id and r.status = 'going'
    )
    else (
      select count(*)::integer
      from public.circle_event_rsvps r
      where r.event_id = p_event_id
    )
  end;
$$;

revoke execute on function public.events2_seats_taken(text, uuid)
  from public, anon, authenticated;

-- Moves people from the waiting list into free seats, in the order they
-- joined. Someone who left the chat or the circle since, or lost sight of the
-- event's channel, is dropped from the list instead. Each person moved up
-- gets a push (event_notices). Returns how many moved up. Run it after
-- anything that can free a seat: an answer that is no longer Going, a bigger
-- capacity, and every few minutes by the sweep.
create or replace function public.events2_promote(p_kind text, p_event_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  seats integer;
  moved integer := 0;
  waiting record;
  chat_row public.chat_events%rowtype;
  circle_row public.circle_events%rowtype;
begin
  if p_kind = 'chat' then
    select e.* into chat_row
    from public.chat_events e
    where e.id = p_event_id
    for update;
    if chat_row.id is null or chat_row.capacity is null or chat_row.cancelled_at is not null then
      return 0;
    end if;
    seats := chat_row.capacity - public.events2_seats_taken('chat', p_event_id);

    for waiting in
      select w.*
      from public.event_waitlist w
      where w.chat_event_id = p_event_id
      order by w.created_at, w.id
      for update skip locked
    loop
      if not exists (
        select 1 from public.conversation_members cm
        where cm.conversation_id = chat_row.conversation_id
          and cm.user_id = waiting.user_id
      ) then
        delete from public.event_waitlist where id = waiting.id;
        continue;
      end if;
      exit when seats <= 0;

      insert into public.chat_event_rsvps (
        event_id, user_id, status, conversation_id, answers
      )
      values (
        p_event_id, waiting.user_id, 'going', chat_row.conversation_id, waiting.answers
      )
      on conflict (event_id, user_id) do update
      set status = 'going', answers = excluded.answers, updated_at = now();
      delete from public.event_waitlist where id = waiting.id;
      insert into public.event_notices (user_id, kind, chat_event_id)
      values (waiting.user_id, 'waitlist_promoted', p_event_id);
      seats := seats - 1;
      moved := moved + 1;
    end loop;
  else
    select e.* into circle_row
    from public.circle_events e
    where e.id = p_event_id
    for update;
    if circle_row.id is null or circle_row.capacity is null or circle_row.cancelled_at is not null then
      return 0;
    end if;
    seats := circle_row.capacity - public.events2_seats_taken('circle', p_event_id);

    for waiting in
      select w.*
      from public.event_waitlist w
      where w.circle_event_id = p_event_id
      order by w.created_at, w.id
      for update skip locked
    loop
      if circle_row.channel_id is not null
        and not public.circle_channel_has_permission(
          circle_row.channel_id, waiting.user_id, 'view_channel'
        )
      then
        delete from public.event_waitlist where id = waiting.id;
        continue;
      end if;
      exit when seats <= 0;

      insert into public.circle_event_rsvps (event_id, circle_id, user_id, answers)
      values (p_event_id, circle_row.circle_id, waiting.user_id, waiting.answers)
      on conflict (event_id, user_id) do update set answers = excluded.answers;
      delete from public.event_waitlist where id = waiting.id;
      insert into public.event_notices (user_id, kind, circle_event_id)
      values (waiting.user_id, 'waitlist_promoted', p_event_id);
      seats := seats - 1;
      moved := moved + 1;
    end loop;
  end if;

  if moved > 0 then
    perform public.wake_scheduled_dispatch();
  end if;
  return moved;
end;
$$;

revoke execute on function public.events2_promote(text, uuid)
  from public, anon, authenticated;
