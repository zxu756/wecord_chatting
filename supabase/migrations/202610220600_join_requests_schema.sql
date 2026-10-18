-- Circle join requests (C1), part 1 of 4: the data, the guard on circle_members
-- and the circle's join settings.
--
-- A circle has a join mode (circles.join_mode):
--
--   * open        anyone who reaches a join path joins at once (what every
--                 circle did until now, and the default);
--   * apply       every join path creates a request instead, and a moderator
--                 (kick_members) approves or denies it. Questions the circle
--                 asks (up to 5, text or single choice) are answered with the
--                 request;
--   * invite_only joining from Discover is closed; invite links and member
--                 invites still work.
--
-- The paths that put someone into a circle (202610220610 changes them):
-- accept_circle_invite (invite links and the 7-day contact card, which carries
-- an invite), join_public_circle (Discover) and invite_circle_members. Each
-- reads the mode first. This file adds the backstop that makes a forgotten
-- path harmless: a BEFORE INSERT trigger on circle_members that refuses any
-- new member of an apply / invite-only circle unless the path vouched for it
-- (see circle_members_require_join_review). Refusing, not redirecting: a path
-- that was not changed fails loudly instead of letting people past review.
--
-- Invites can carry "skip review" (circle_invites.skip_review). It only counts
-- while its creator still has BOTH create_invites and kick_members.

alter table public.circles
  add column if not exists join_mode text not null default 'open';

alter table public.circles
  drop constraint if exists circles_join_mode_check;
alter table public.circles
  add constraint circles_join_mode_check
  check (join_mode in ('open', 'apply', 'invite_only'));

alter table public.circle_invites
  add column if not exists skip_review boolean not null default false;

-- ---------------------------------------------------------------------------
-- Questions
-- ---------------------------------------------------------------------------

create table if not exists public.circle_join_questions (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  position smallint not null check (position between 0 and 4),
  kind text not null check (kind in ('text', 'choice')),
  prompt text not null check (char_length(btrim(prompt)) between 1 and 200),
  options text[] not null default '{}',
  required boolean not null default true,
  created_at timestamptz not null default now(),
  constraint circle_join_questions_position_unique unique (circle_id, position),
  constraint circle_join_questions_options_match check (
    (kind = 'text' and cardinality(options) = 0)
    or (kind = 'choice' and cardinality(options) between 2 and 8)
  )
);

-- Read and written through the RPCs below only.
alter table public.circle_join_questions enable row level security;
revoke all on public.circle_join_questions from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Requests
-- ---------------------------------------------------------------------------

create table if not exists public.circle_join_requests (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- [{question_id, prompt, kind, answer}]: a copy of the question as it
  -- read when the person answered, so editing the questions later changes
  -- nothing here.
  answers jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'denied')),
  -- Set when a member invited the person (invite_circle_members).
  invited_by uuid references public.profiles(id) on delete set null,
  decided_by uuid references public.profiles(id) on delete set null,
  decided_at timestamptz,
  -- A reason a moderator may give; the applicant reads it.
  note text,
  created_at timestamptz not null default now(),
  -- The decision's push was handed to scheduled-dispatch (once).
  push_claimed_at timestamptz,
  -- The applicant dismissed the result card in Notifications.
  seen_at timestamptz,
  constraint circle_join_requests_answers_array
    check (jsonb_typeof(answers) = 'array'),
  constraint circle_join_requests_decided_pair
    check ((status = 'pending') = (decided_at is null)),
  constraint circle_join_requests_note_length
    check (note is null or char_length(note) <= 500)
);

create unique index if not exists circle_join_requests_one_pending_idx
  on public.circle_join_requests (circle_id, user_id)
  where status = 'pending';

create index if not exists circle_join_requests_queue_idx
  on public.circle_join_requests (circle_id, status, created_at desc);

create index if not exists circle_join_requests_user_idx
  on public.circle_join_requests (user_id, created_at desc);

create index if not exists circle_join_requests_unpushed_idx
  on public.circle_join_requests (decided_at)
  where push_claimed_at is null and status <> 'pending';

alter table public.circle_join_requests enable row level security;
revoke all on public.circle_join_requests from public, anon, authenticated;
grant select on public.circle_join_requests to authenticated;

-- The applicant reads their own; moderators of the circle read its queue.
drop policy if exists circle_join_requests_select on public.circle_join_requests;
create policy circle_join_requests_select
  on public.circle_join_requests for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.current_user_has_circle_permission(circle_id, 'kick_members')
  );

-- A request for a circle that is down or that bans the person is refused
-- whatever path made it.
create or replace function public.reject_blocked_join_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.circles c
    where c.id = new.circle_id and c.disabled_at is not null
  ) then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.circle_bans b
    where b.circle_id = new.circle_id and b.user_id = new.user_id
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_blocked_join_request()
  from public, anon, authenticated;

drop trigger if exists circle_join_requests_reject_blocked on public.circle_join_requests;
create trigger circle_join_requests_reject_blocked
  before insert on public.circle_join_requests
  for each row execute function public.reject_blocked_join_request();

-- ---------------------------------------------------------------------------
-- The guard on circle_members
-- ---------------------------------------------------------------------------

-- Lets the rest of this transaction add members to [target_circle_id]: the
-- path has done the join-mode check itself (an approved request, an invite
-- that skips review, an exempt inviter, an invite-only circle's invite). The
-- setting lives and dies with the transaction.
create or replace function public.allow_circle_join(target_circle_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  select set_config('wecord.join_bypass', target_circle_id::text, true);
$$;

create or replace function public.close_circle_join()
returns void
language sql
security definer
set search_path = public
as $$
  select set_config('wecord.join_bypass', '', true);
$$;

revoke execute on function public.allow_circle_join(uuid) from public, anon, authenticated;
revoke execute on function public.close_circle_join() from public, anon, authenticated;

-- BEFORE INSERT on circle_members. In an apply or invite-only circle a signed
-- in person is only added by a path that opened allow_circle_join for this
-- circle. Not held back: the circle's own owner row, bots (a manager adds
-- them), and statements without a signed-in person (service role, migrations,
-- admin tooling). Named to fire after the ban and take-down triggers, so
-- those refusals read first.
create or replace function public.circle_members_require_join_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  mode text;
begin
  select c.join_mode into mode
  from public.circles c
  where c.id = new.circle_id;

  if mode is null or mode = 'open' then
    return new;
  end if;

  if auth.uid() is null
    or new.role = 'owner'
    or current_setting('wecord.join_bypass', true) = new.circle_id::text
    or exists (
      select 1 from public.profiles p
      where p.id = new.user_id and p.is_bot
    )
  then
    return new;
  end if;

  raise exception 'This circle reviews who joins' using
    errcode = '42501',
    detail = 'join_review_required';
end;
$$;

revoke execute on function public.circle_members_require_join_review()
  from public, anon, authenticated;

drop trigger if exists circle_members_require_review on public.circle_members;
create trigger circle_members_require_review
  before insert on public.circle_members
  for each row execute function public.circle_members_require_join_review();

-- ---------------------------------------------------------------------------
-- Who is exempt
-- ---------------------------------------------------------------------------

-- Whether [inviter] may bring people in without review: both create_invites
-- and kick_members (the reviewing permission) in the circle.
create or replace function public.can_skip_join_review(
  target_circle_id uuid,
  inviter uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select inviter is not null
    and public.circle_member_has_permission(
      target_circle_id, inviter, 'create_invites')
    and public.circle_member_has_permission(
      target_circle_id, inviter, 'kick_members');
$$;

revoke execute on function public.can_skip_join_review(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Join settings: the mode and the questions (manage_circle)
-- ---------------------------------------------------------------------------

create or replace function public.circle_join_questions_json(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', q.id,
        'kind', q.kind,
        'prompt', q.prompt,
        'options', to_jsonb(q.options),
        'required', q.required
      )
      order by q.position
    ),
    '[]'::jsonb
  )
  from public.circle_join_questions q
  where q.circle_id = target_circle_id;
$$;

revoke execute on function public.circle_join_questions_json(uuid)
  from public, anon, authenticated;

create or replace function public.get_circle_join_settings(target_circle_id uuid)
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

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who can manage the circle can see join settings'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'join_mode', (select c.join_mode from public.circles c where c.id = target_circle_id),
    'questions', public.circle_join_questions_json(target_circle_id)
  );
end;
$$;

-- Sets the mode and replaces the questions: question_list is an array of
-- {id?, kind: 'text'|'choice', prompt, options: [..], required}.
create or replace function public.set_circle_join_settings(
  target_circle_id uuid,
  new_mode text,
  question_list jsonb default '[]'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  old_mode text;
  old_questions jsonb;
  new_questions jsonb;
  item jsonb;
  position_index smallint := 0;
  question_kind text;
  question_prompt text;
  question_options text[];
  question_id uuid;
  changes jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who can manage the circle can change join settings'
      using errcode = '42501';
  end if;

  if new_mode is null or new_mode not in ('open', 'apply', 'invite_only') then
    raise exception 'Unknown join mode' using errcode = '22023';
  end if;

  question_list := coalesce(question_list, '[]'::jsonb);
  if jsonb_typeof(question_list) <> 'array' then
    raise exception 'Questions must be a list' using errcode = '22023';
  end if;
  if jsonb_array_length(question_list) > 5 then
    raise exception 'Up to 5 questions' using errcode = '22023';
  end if;

  select c.join_mode into old_mode
  from public.circles c
  where c.id = target_circle_id
  for update;
  if old_mode is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  old_questions := public.circle_join_questions_json(target_circle_id);

  -- Check everything before writing anything.
  for item in select value from jsonb_array_elements(question_list)
  loop
    question_kind := item ->> 'kind';
    question_prompt := btrim(coalesce(item ->> 'prompt', ''));
    if question_kind is null or question_kind not in ('text', 'choice') then
      raise exception 'Unknown question type' using errcode = '22023';
    end if;
    if char_length(question_prompt) not between 1 and 200 then
      raise exception 'A question is 1 to 200 characters' using errcode = '22023';
    end if;
    if question_kind = 'choice' then
      select coalesce(array_agg(btrim(o.value) order by o.ordinality), '{}')
      into question_options
      from jsonb_array_elements_text(coalesce(item -> 'options', '[]'::jsonb))
        with ordinality as o(value, ordinality)
      where btrim(o.value) <> '';
      if cardinality(question_options) not between 2 and 8
        or exists (select 1 from unnest(question_options) x where char_length(x) > 100)
        or (select count(distinct x) from unnest(question_options) x)
          <> cardinality(question_options)
      then
        raise exception 'A choice question has 2 to 8 different options of up to 100 characters'
          using errcode = '22023';
      end if;
    end if;
  end loop;

  delete from public.circle_join_questions where circle_id = target_circle_id;

  for item in select value from jsonb_array_elements(question_list)
  loop
    question_kind := item ->> 'kind';
    question_prompt := btrim(item ->> 'prompt');
    question_options := '{}';
    if question_kind = 'choice' then
      select coalesce(array_agg(btrim(o.value) order by o.ordinality), '{}')
      into question_options
      from jsonb_array_elements_text(item -> 'options') with ordinality as o(value, ordinality)
      where btrim(o.value) <> '';
    end if;
    question_id := case
      when coalesce(item ->> 'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (item ->> 'id')::uuid
      else gen_random_uuid()
    end;
    insert into public.circle_join_questions (
      id, circle_id, position, kind, prompt, options, required
    )
    values (
      question_id,
      target_circle_id,
      position_index,
      question_kind,
      question_prompt,
      question_options,
      coalesce((item ->> 'required')::boolean, true)
    )
    on conflict (id) do nothing;
    position_index := position_index + 1;
  end loop;

  update public.circles set join_mode = new_mode where id = target_circle_id;

  new_questions := public.circle_join_questions_json(target_circle_id);

  if old_mode is distinct from new_mode then
    changes := changes || jsonb_build_object(
      'join_mode', jsonb_build_object('old', old_mode, 'new', new_mode)
    );
  end if;
  -- Compared without the ids, which a save may renew.
  if (select coalesce(jsonb_agg(q - 'id'), '[]'::jsonb) from jsonb_array_elements(old_questions) q)
    is distinct from
    (select coalesce(jsonb_agg(q - 'id'), '[]'::jsonb) from jsonb_array_elements(new_questions) q)
  then
    changes := changes || jsonb_build_object(
      'questions', jsonb_build_object(
        'old', jsonb_array_length(old_questions),
        'new', jsonb_array_length(new_questions)
      )
    );
  end if;

  if changes <> '{}'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'join_settings_update',
      'circle',
      target_circle_id,
      (select c.name from public.circles c where c.id = target_circle_id),
      changes
    );
  end if;
end;
$$;

revoke execute on function public.get_circle_join_settings(uuid) from public, anon;
revoke execute on function public.set_circle_join_settings(uuid, text, jsonb) from public, anon;
grant execute on function public.get_circle_join_settings(uuid) to authenticated;
grant execute on function public.set_circle_join_settings(uuid, text, jsonb) to authenticated;
