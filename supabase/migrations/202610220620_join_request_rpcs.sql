-- Circle join requests (C1), part 3 of 4: what the applicant and the
-- moderators call.
--
-- Applicant
--   * get_circle_join_state(circle, invite_code?): where the person stands in
--     a circle: its join mode, the questions to answer (only while they must
--     be answered), and their latest request. Visible to anyone who may see
--     the circle: it is public, or they are a member, or they have a request,
--     or they hold a usable invite. Null otherwise.
--   * list_my_join_requests(): requests still waiting, and answers they have
--     not dismissed yet (30 days), for the Notifications page.
--   * cancel_join_request(circle), dismiss_join_request_result(request).
--
-- Moderators (kick_members, the permission that also lets them let people in)
--   * count_join_requests(circle), list_join_requests(circle).
--   * decide_join_request(request, approve, note): approving adds the person
--     as an ordinary member of the circle and its channels (rules they still
--     have to accept, welcome message, the AI guard's new member window all
--     start now); denying keeps the optional note for the applicant. Both
--     write the circle's audit log and wake scheduled-dispatch, which pushes
--     the answer (202610220630).

create or replace function public.circle_join_request_json(request public.circle_join_requests)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', request.id,
    'status', request.status,
    'created_at', request.created_at,
    'decided_at', request.decided_at,
    'note', request.note,
    'invited', request.invited_by is not null
  );
$$;

revoke execute on function public.circle_join_request_json(public.circle_join_requests)
  from public, anon, authenticated;

create or replace function public.get_circle_join_state(
  target_circle_id uuid,
  invite_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  circle public.circles%rowtype;
  latest public.circle_join_requests%rowtype;
  target_invite public.circle_invites%rowtype;
  is_member boolean;
  invite_usable boolean := false;
  skips boolean := false;
  must_answer boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id;
  if circle.id is null then
    return null;
  end if;

  is_member := exists (
    select 1 from public.circle_members cm
    where cm.circle_id = circle.id and cm.user_id = current_user_id
  );

  select r.* into latest
  from public.circle_join_requests r
  where r.circle_id = circle.id and r.user_id = current_user_id
  order by r.created_at desc
  limit 1;

  if invite_code is not null then
    select * into target_invite
    from public.circle_invites ci
    where ci.code = lower(trim(invite_code))
      and ci.circle_id = circle.id;
    invite_usable := target_invite.code is not null
      and public.circle_invite_invalid_reason(target_invite) is null
      and not public.are_users_blocked(target_invite.created_by, current_user_id);
    skips := invite_usable
      and target_invite.skip_review
      and public.can_skip_join_review(circle.id, target_invite.created_by);
  end if;

  if not (circle.is_public or is_member or latest.id is not null or invite_usable) then
    return null;
  end if;

  must_answer := circle.join_mode = 'apply' and not is_member and not skips;

  return jsonb_build_object(
    'circle_id', circle.id,
    'join_mode', circle.join_mode,
    'closed', circle.disabled_at is not null,
    'is_member', is_member,
    'skip_review', skips,
    'questions', case
      when must_answer then public.circle_join_questions_json(circle.id)
      else '[]'::jsonb
    end,
    'request', case
      when latest.id is null then null
      else public.circle_join_request_json(latest)
    end,
    'retry_at', case
      when latest.status = 'denied' and latest.decided_at > now() - interval '24 hours'
        then latest.decided_at + interval '24 hours'
      else null
    end
  );
end;
$$;

create or replace function public.list_my_join_requests()
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

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'circle_id', c.id,
        'circle_name', c.name,
        'circle_avatar_url', c.avatar_url,
        'status', r.status,
        'note', r.note,
        'created_at', r.created_at,
        'decided_at', r.decided_at,
        'invited', r.invited_by is not null,
        'is_member', exists (
          select 1 from public.circle_members cm
          where cm.circle_id = c.id and cm.user_id = r.user_id
        )
      )
      order by coalesce(r.decided_at, r.created_at) desc
    )
    from public.circle_join_requests r
    join public.circles c on c.id = r.circle_id
    where r.user_id = auth.uid()
      and (
        r.status = 'pending'
        or (
          r.seen_at is null
          and r.decided_at > now() - interval '30 days'
        )
      )
  ), '[]'::jsonb);
end;
$$;

create or replace function public.cancel_join_request(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.circle_join_requests r
  where r.circle_id = target_circle_id
    and r.user_id = auth.uid()
    and r.status = 'pending';
end;
$$;

create or replace function public.dismiss_join_request_result(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.circle_join_requests r
  set seen_at = now()
  where r.id = request_id
    and r.user_id = auth.uid()
    and r.status <> 'pending'
    and r.seen_at is null;
end;
$$;

create or replace function public.count_join_requests(target_circle_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'kick_members') then
    return 0;
  end if;

  return (
    select least(count(*), 99)::integer
    from public.circle_join_requests r
    where r.circle_id = target_circle_id and r.status = 'pending'
  );
end;
$$;

create or replace function public.list_join_requests(
  target_circle_id uuid,
  page_size integer default 50
)
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

  if not public.current_user_has_circle_permission(target_circle_id, 'kick_members') then
    raise exception 'Only members who can remove members can review join requests'
      using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(row_json order by created_at)
    from (
      select
        r.created_at,
        jsonb_build_object(
          'id', r.id,
          'user_id', p.id,
          'display_name', p.display_name,
          'username', p.username,
          'avatar_url', p.avatar_url,
          'account_created_at', p.created_at,
          'created_at', r.created_at,
          'answers', r.answers,
          'invited_by_name', (
            select coalesce(nullif(btrim(ip.display_name), ''), ip.username)
            from public.profiles ip
            where ip.id = r.invited_by
          )
        ) as row_json
      from public.circle_join_requests r
      join public.profiles p on p.id = r.user_id
      where r.circle_id = target_circle_id
        and r.status = 'pending'
      order by r.created_at
      limit least(greatest(coalesce(page_size, 50), 1), 100)
    ) pending
  ), '[]'::jsonb);
end;
$$;

create or replace function public.decide_join_request(
  request_id uuid,
  approve boolean,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target public.circle_join_requests%rowtype;
  cleaned_note text := nullif(btrim(coalesce(decision_note, '')), '');
  changes jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select r.* into target
  from public.circle_join_requests r
  where r.id = decide_join_request.request_id
  for update;

  if target.id is null
    or not public.current_user_has_circle_permission(target.circle_id, 'kick_members')
  then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;

  if target.user_id = current_user_id then
    raise exception 'You cannot decide your own request' using errcode = '42501';
  end if;

  if target.status <> 'pending' then
    raise exception 'Request already decided' using errcode = '22023';
  end if;

  if cleaned_note is not null and char_length(cleaned_note) > 500 then
    raise exception 'A note is up to 500 characters' using errcode = '22023';
  end if;

  if approve then
    -- The ban and take-down triggers still apply: a person banned since they
    -- applied cannot be let in.
    perform public.allow_circle_join(target.circle_id);

    insert into public.circle_members (circle_id, user_id, role)
    values (target.circle_id, target.user_id, 'member')
    on conflict do nothing;

    perform public.close_circle_join();

    insert into public.conversation_members (conversation_id, user_id, role)
    select cc.conversation_id, target.user_id, 'member'
    from public.circle_channels cc
    where cc.circle_id = target.circle_id
    on conflict do nothing;
  end if;

  update public.circle_join_requests r
  set status = case when approve then 'approved' else 'denied' end,
      decided_by = current_user_id,
      decided_at = now(),
      note = cleaned_note
  where r.id = target.id;

  changes := jsonb_build_object('answers', jsonb_array_length(target.answers));
  if cleaned_note is not null then
    changes := changes || jsonb_build_object('note', cleaned_note);
  end if;

  perform public.write_circle_audit(
    target.circle_id,
    case when approve then 'join_request_approve' else 'join_request_deny' end,
    'member',
    target.user_id,
    public.circle_member_label(target.circle_id, target.user_id),
    changes
  );

  perform public.wake_scheduled_dispatch();
end;
$$;

revoke execute on function public.get_circle_join_state(uuid, text) from public, anon;
revoke execute on function public.list_my_join_requests() from public, anon;
revoke execute on function public.cancel_join_request(uuid) from public, anon;
revoke execute on function public.dismiss_join_request_result(uuid) from public, anon;
revoke execute on function public.count_join_requests(uuid) from public, anon;
revoke execute on function public.list_join_requests(uuid, integer) from public, anon;
revoke execute on function public.decide_join_request(uuid, boolean, text) from public, anon;
grant execute on function public.get_circle_join_state(uuid, text) to authenticated;
grant execute on function public.list_my_join_requests() to authenticated;
grant execute on function public.cancel_join_request(uuid) to authenticated;
grant execute on function public.dismiss_join_request_result(uuid) to authenticated;
grant execute on function public.count_join_requests(uuid) to authenticated;
grant execute on function public.list_join_requests(uuid, integer) to authenticated;
grant execute on function public.decide_join_request(uuid, boolean, text) to authenticated;
