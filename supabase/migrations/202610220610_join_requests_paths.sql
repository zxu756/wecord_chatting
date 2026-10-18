-- Circle join requests (C1), part 2 of 4: every join path reads the circle's
-- join mode first.
--
-- A request is made by submit_circle_join_request, the one place that checks
-- the circle is up, the person is not banned, they have no request waiting,
-- the 24 hour wait after a denial, the 20 open requests per person, and that
-- the answers fit the circle's questions.
--
-- The paths, each rewritten from its newest definition:
--
--   * accept_circle_invite (202610130003; invite links, and the 7-day contact
--     card, whose button opens the same invite page). open: as before.
--     apply: a request, unless the invite skips review (its creator still has
--     create_invites AND kick_members). invite_only: joins, an invite is the
--     way in. Takes the answers as a second argument.
--   * join_public_circle (202610210120, which added the take-down check).
--     open: as before. apply: a request. invite_only: refused.
--   * invite_circle_members (202610130018; a member adds friends). open and
--     invite_only: as before. apply: a request per person (invited_by is the
--     member), unless the member has create_invites AND kick_members.
--   * send_contact_card (202610180071): only so a card never reuses an invite
--     that skips review.
--
-- All of these return what they returned (the circle id), also when a request
-- was made instead: ask get_circle_join_state for where the person stands.
-- Bans, the take-down trigger, onboarding (rules_accepted_at stays null until
-- the person accepts), the AI guard's "new member since" (circle_members
-- .created_at is the day they were let in) and the invite use count keep
-- working as they did. circle_members_require_join_review (202610220600)
-- refuses any path that forgets the mode.

create or replace function public.submit_circle_join_request(
  target_circle_id uuid,
  applicant uuid,
  answer_list jsonb default null,
  inviter uuid default null,
  check_answers boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
  request_id uuid;
  stored_answers jsonb := '[]'::jsonb;
  question record;
  given jsonb;
  given_text text;
begin
  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for share;

  if circle.id is null then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;
  if circle.disabled_at is not null then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.circle_bans b
    where b.circle_id = circle.id and b.user_id = applicant
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;

  select r.id into request_id
  from public.circle_join_requests r
  where r.circle_id = circle.id
    and r.user_id = applicant
    and r.status = 'pending';
  if request_id is not null then
    return request_id;
  end if;

  if inviter is null then
    if exists (
      select 1 from public.circle_join_requests r
      where r.circle_id = circle.id
        and r.user_id = applicant
        and r.status = 'denied'
        and r.decided_at > now() - interval '24 hours'
    ) then
      raise exception 'Your request was declined. You can apply again tomorrow.'
        using errcode = 'PB429';
    end if;
    if (
      select count(*) from public.circle_join_requests r
      where r.user_id = applicant and r.status = 'pending'
    ) >= 20 then
      raise exception 'Too many open requests. Wait for an answer first.'
        using errcode = 'PB429';
    end if;
  end if;

  if check_answers then
    answer_list := coalesce(answer_list, '[]'::jsonb);
    if jsonb_typeof(answer_list) <> 'array' then
      raise exception 'Answers must be a list' using errcode = '22023';
    end if;
    for question in
      select q.* from public.circle_join_questions q
      where q.circle_id = circle.id
      order by q.position
    loop
      select a.value into given
      from jsonb_array_elements(answer_list) a(value)
      where a.value ->> 'question_id' = question.id::text
      limit 1;
      given_text := btrim(coalesce(given ->> 'answer', ''));
      if given_text = '' then
        if question.required then
          raise exception 'Answer the required questions' using
            errcode = '22023', detail = 'answers_required';
        end if;
        continue;
      end if;
      if char_length(given_text) > 500 then
        raise exception 'An answer is up to 500 characters' using errcode = '22023';
      end if;
      if question.kind = 'choice' and not (given_text = any (question.options)) then
        raise exception 'Choose one of the options' using errcode = '22023';
      end if;
      stored_answers := stored_answers || jsonb_build_array(jsonb_build_object(
        'question_id', question.id,
        'prompt', question.prompt,
        'kind', question.kind,
        'answer', given_text
      ));
    end loop;
  end if;

  insert into public.circle_join_requests (
    circle_id, user_id, answers, invited_by
  )
  values (circle.id, applicant, stored_answers, inviter)
  returning id into request_id;

  return request_id;
end;
$$;

revoke execute on function public.submit_circle_join_request(uuid, uuid, jsonb, uuid, boolean)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- accept_circle_invite: 202610130003 plus the join mode and the answers
-- ---------------------------------------------------------------------------

drop function if exists public.accept_circle_invite(text);

create or replace function public.accept_circle_invite(
  invite_code text,
  answers jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_invite public.circle_invites%rowtype;
  invalid_reason text;
  circle public.circles%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select *
  into target_invite
  from public.circle_invites
  where code = lower(trim(coalesce(invite_code, '')))
  for update;

  if target_invite.code is null
    or public.are_users_blocked(target_invite.created_by, current_user_id)
  then
    raise exception 'Invite not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_invite.circle_id
      and cm.user_id = current_user_id
  ) then
    return target_invite.circle_id;
  end if;

  invalid_reason := public.circle_invite_invalid_reason(target_invite);
  if invalid_reason is not null then
    raise exception 'Invite is %', invalid_reason using errcode = '22023';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_invite.circle_id;

  if circle.join_mode = 'apply'
    and not (
      target_invite.skip_review
      and public.can_skip_join_review(circle.id, target_invite.created_by)
    )
  then
    -- Waiting already: nothing more to do, and no second use is spent.
    if exists (
      select 1 from public.circle_join_requests r
      where r.circle_id = circle.id
        and r.user_id = current_user_id
        and r.status = 'pending'
    ) then
      return circle.id;
    end if;

    perform public.submit_circle_join_request(
      circle.id, current_user_id, accept_circle_invite.answers, null, true);

    update public.circle_invites
    set use_count = use_count + 1
    where code = target_invite.code;

    return circle.id;
  end if;

  -- open, invite only, or an invite that skips review.
  perform public.allow_circle_join(circle.id);

  insert into public.circle_members (circle_id, user_id, role)
  values (target_invite.circle_id, current_user_id, 'member')
  on conflict do nothing;

  perform public.close_circle_join();

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, current_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = target_invite.circle_id
  on conflict do nothing;

  update public.circle_invites
  set use_count = use_count + 1
  where code = target_invite.code;

  return target_invite.circle_id;
end;
$$;

revoke execute on function public.accept_circle_invite(text, jsonb) from public, anon;
grant execute on function public.accept_circle_invite(text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- join_public_circle: 202610210120 plus the join mode and the answers
-- ---------------------------------------------------------------------------

drop function if exists public.join_public_circle(uuid);

create or replace function public.join_public_circle(
  target_circle_id uuid,
  answers jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  circle public.circles%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for share;

  if circle.id is null or not circle.is_public then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = circle.id
      and cm.user_id = current_user_id
  ) then
    return circle.id;
  end if;

  if circle.disabled_at is not null then
    raise exception 'This circle is not accepting new members'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.circle_bans b
    where b.circle_id = circle.id
      and b.user_id = current_user_id
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;

  if circle.join_mode = 'invite_only' then
    raise exception 'This circle is invite only' using
      errcode = '42501', detail = 'invite_only';
  end if;

  if circle.join_mode = 'apply' then
    perform public.submit_circle_join_request(
      circle.id, current_user_id, join_public_circle.answers, null, true);
    return circle.id;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('public-join:' || current_user_id::text, 0));

  delete from public.circle_public_joins j
  where j.user_id = current_user_id
    and j.joined_at < now() - interval '1 day';

  if (
    select count(*)
    from public.circle_public_joins j
    where j.user_id = current_user_id
      and j.joined_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception 'Too many circles joined. Try again later.'
      using errcode = 'PB429';
  end if;

  insert into public.circle_members (circle_id, user_id, role)
  values (circle.id, current_user_id, 'member')
  on conflict do nothing;

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, current_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = circle.id
  on conflict do nothing;

  insert into public.circle_public_joins (user_id, circle_id)
  values (current_user_id, circle.id);

  return circle.id;
end;
$$;

revoke execute on function public.join_public_circle(uuid, jsonb) from public, anon;
grant execute on function public.join_public_circle(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- invite_circle_members: 202610130018 plus the join mode
-- ---------------------------------------------------------------------------

create or replace function public.invite_circle_members(
  target_circle_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  added_members jsonb;
  invited_member uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'create_invites'
  ) then
    raise exception 'Only members who can create invites can invite members'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where candidate.member_id is null
      or candidate.member_id = current_user_id
      or not exists (
        select 1
        from public.profiles p
        where p.id = candidate.member_id
      )
      or not exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(current_user_id, candidate.member_id)
          and f.user_high_id = greatest(current_user_id, candidate.member_id)
      )
      or public.are_users_blocked(current_user_id, candidate.member_id)
  ) then
    raise exception 'Invalid circle invite members' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    join public.circle_members cm
      on cm.circle_id = target_circle_id
      and cm.user_id = candidate.member_id
  ) then
    raise exception 'User is already a circle member' using errcode = '23505';
  end if;

  -- A circle that reviews who joins: the friends become requests, unless the
  -- member may skip review (create_invites and kick_members).
  if (select c.join_mode from public.circles c where c.id = target_circle_id) = 'apply'
    and not public.can_skip_join_review(target_circle_id, current_user_id)
  then
    for invited_member in
      select distinct candidate.member_id
      from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
      where candidate.member_id is not null
        and candidate.member_id <> current_user_id
    loop
      perform public.submit_circle_join_request(
        target_circle_id, invited_member, null, current_user_id, false);
    end loop;
    return;
  end if;

  perform public.allow_circle_join(target_circle_id);

  with invited as (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ),
  allowed as (
    select invited.member_id
    from invited
    where exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, invited.member_id)
        and f.user_high_id = greatest(current_user_id, invited.member_id)
    )
      and not public.are_users_blocked(current_user_id, invited.member_id)
  ),
  inserted as (
    insert into public.circle_members (circle_id, user_id, role)
    select target_circle_id, allowed.member_id, 'member'
    from allowed
    on conflict do nothing
    returning user_id
  ),
  joined_channels as (
    insert into public.conversation_members (conversation_id, user_id, role)
    select cc.conversation_id, inserted.user_id, 'member'
    from inserted
    cross join public.circle_channels cc
    where cc.circle_id = target_circle_id
    on conflict do nothing
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', p.id,
        'name', coalesce(nullif(btrim(p.display_name), ''), p.username)
      )
      order by p.display_name
    ),
    '[]'::jsonb
  )
  into added_members
  from inserted
  join public.profiles p on p.id = inserted.user_id;

  perform public.close_circle_join();

  if added_members <> '[]'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'member_add',
      'member',
      case
        when jsonb_array_length(added_members) = 1
          then (added_members -> 0 ->> 'id')::uuid
      end,
      (
        select string_agg(member.value ->> 'name', ', ' order by member.ordinality)
        from jsonb_array_elements(added_members) with ordinality as member(value, ordinality)
      ),
      jsonb_build_object('members', added_members)
    );
  end if;
end;
$$;

revoke execute on function public.invite_circle_members(uuid, uuid[]) from public, anon;
grant execute on function public.invite_circle_members(uuid, uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Invites that skip review
-- ---------------------------------------------------------------------------

-- create_circle_invite with a fourth argument (no default, so the three
-- argument call keeps resolving to the original). Skipping review needs both
-- create_invites and kick_members; the entry is audited.
create or replace function public.create_circle_invite(
  target_circle_id uuid,
  expires_in_hours integer,
  max_uses integer,
  skip_review boolean
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  created_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if coalesce(skip_review, false)
    and not public.can_skip_join_review(target_circle_id, auth.uid())
  then
    raise exception 'Only members who can create invites and remove members can skip review'
      using errcode = '42501';
  end if;

  created_code := public.create_circle_invite(
    target_circle_id,
    create_circle_invite.expires_in_hours,
    create_circle_invite.max_uses
  );

  if coalesce(skip_review, false) then
    update public.circle_invites ci
    set skip_review = true
    where ci.code = created_code;

    perform public.write_circle_audit(
      target_circle_id,
      'invite_skip_review',
      'invite',
      null,
      created_code,
      jsonb_build_object('code', created_code)
    );
  end if;

  return created_code;
end;
$$;

revoke execute on function public.create_circle_invite(uuid, integer, integer, boolean)
  from public, anon;
grant execute on function public.create_circle_invite(uuid, integer, integer, boolean)
  to authenticated;

-- The codes of this circle's invites that skip review, for the invite list.
create or replace function public.list_circle_invites_skipping_review(
  target_circle_id uuid
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.current_user_has_circle_permission(target_circle_id, 'create_invites') then
    raise exception 'Only members who can create invites can see them'
      using errcode = '42501';
  end if;
  return coalesce((
    select array_agg(ci.code order by ci.created_at desc)
    from public.circle_invites ci
    where ci.circle_id = target_circle_id
      and ci.skip_review
      and ci.revoked_at is null
  ), '{}');
end;
$$;

revoke execute on function public.list_circle_invites_skipping_review(uuid) from public, anon;
grant execute on function public.list_circle_invites_skipping_review(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- send_contact_card: 202610180071; the card's reused invite never skips review
-- ---------------------------------------------------------------------------

create or replace function public.send_contact_card(
  target_conversation_id uuid,
  card_kind text,
  card_target_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  profile_row public.profiles%rowtype;
  circle_row public.circles%rowtype;
  member_total integer;
  invite_code text;
  card jsonb;
  label text;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if card_kind not in ('user', 'circle') or card_target_id is null then
    raise exception 'Unknown contact card' using errcode = '22023';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id)
    or not public.can_current_user_send_in_conversation(target_conversation_id)
  then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  if card_kind = 'user' then
    select * into profile_row
    from public.profiles p
    where p.id = card_target_id
      and p.deleted_at is null;

    if profile_row.id is null
      or public.are_users_blocked(current_user_id, card_target_id)
      or not public.can_view_profile_details(card_target_id)
    then
      raise exception 'This contact cannot be shared' using errcode = '42501';
    end if;

    label := profile_row.display_name;
    card := jsonb_strip_nulls(jsonb_build_object(
      'kind', 'contact_card',
      'card', 'user',
      'user_id', profile_row.id,
      'name', profile_row.display_name,
      'username', profile_row.username,
      'avatar_url', profile_row.avatar_url
    ));
  else
    select * into circle_row
    from public.circles c
    where c.id = card_target_id;

    if circle_row.id is null
      or not public.current_user_has_circle_permission(
        card_target_id,
        'create_invites'
      )
    then
      raise exception 'This circle cannot be shared' using errcode = '42501';
    end if;

    select ci.code
    into invite_code
    from public.circle_invites ci
    where ci.circle_id = card_target_id
      and ci.created_by = current_user_id
      and ci.revoked_at is null
      and not ci.skip_review
      and ci.max_uses is null
      and ci.expires_at > now() + interval '1 day'
      and ci.expires_at < now() + interval '8 days'
    order by ci.created_at desc
    limit 1;

    if invite_code is null then
      invite_code := public.create_circle_invite(card_target_id, 168, null);
    end if;

    select count(*)
    into member_total
    from public.circle_members cm
    where cm.circle_id = card_target_id;

    label := circle_row.name;
    card := jsonb_strip_nulls(jsonb_build_object(
      'kind', 'contact_card',
      'card', 'circle',
      'circle_id', circle_row.id,
      'name', circle_row.name,
      'avatar_url', circle_row.avatar_url,
      'member_count', member_total,
      'invite_code', invite_code
    ));
  end if;

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    current_user_id,
    'text',
    'Contact card: ' || label,
    card
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

revoke execute on function public.send_contact_card(uuid, text, uuid)
  from public, anon;
grant execute on function public.send_contact_card(uuid, text, uuid)
  to authenticated;
