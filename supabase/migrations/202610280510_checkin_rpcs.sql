-- Group check-in (roadmap D3), part 2 of 4: making a check-in, checking in,
-- and reading.
--
-- * create_check_in(conversation, title, ...) posts the card (a message with
--   attachment {kind: 'check_in', check_in_id, title}, body "✅ <title>") and
--   the board. Groups and circle channels only (chain_conversation_allowed,
--   202610180060), by anyone who may send there. The zone is the creator's
--   device zone (bad names count as UTC); the last day and the daily reminder
--   are optional.
-- * submit_check_in(check_in, note, photo) checks in for the board's today.
--   The same call on the same day edits the note and the picture. It checks
--   membership (a circle an admin suspended, K1, counts as no membership),
--   suspended accounts, the right to send, blocking, that the board is open,
--   and that the picture is a file of this conversation's check-in folder
--   uploaded by the caller. The note is free text: for a member the AI guard
--   would hold it is dropped (note_held = true), as a chain's note is
--   (chain_note_needs_review). In a circle channel the check-in is also a day
--   of activity for the circle (circle_member_daily), which C7's streak reads.
-- * undo_check_in(check_in) takes today's check-in back.
-- * set_check_in_closed(check_in, closed) closes or reopens (the creator and
--   whoever moderates the conversation; reopening drops a last day that has
--   passed).
-- * get_check_in(check_in) is everything the card and its page show in one
--   read: the board, the counts for today, the caller's run and days, today's
--   check-ins (not people the caller blocked or who blocked them), the
--   longest live runs and what the caller may do. get_check_ins(ids) is the
--   short form for a batch of cards. get_check_in_day(check_in, day) lists
--   another day. Blocked people never appear in a list; counts are counts.

-- Members who count towards "18/30": people (no bots, no deleted accounts)
-- who can see the conversation.
create or replace function public.check_in_member_total(p_conversation_id uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = p_conversation_id
    and not coalesce(p.is_bot, false)
    and p.deleted_at is null
    and (
      not exists (
        select 1
        from public.circle_channels cc
        join public.circle_channel_overwrites o on o.channel_id = cc.id
        where cc.conversation_id = p_conversation_id
      )
      or public.user_has_conversation_channel_permission(
        p_conversation_id, cm.user_id, 'view_channel'
      )
    );
$$;

revoke execute on function public.check_in_member_total(uuid)
  from public, anon, authenticated;

-- Who may close, reopen and (with the creator) manage a board.
create or replace function public.check_in_can_manage(board public.check_in_boards)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;
  return board.created_by = auth.uid()
    or public.can_current_user_moderate_polls(board.conversation_id);
end;
$$;

revoke execute on function public.check_in_can_manage(public.check_in_boards)
  from public, anon, authenticated;

-- A person's name in a conversation: their nickname in the circle when it is
-- a circle channel, else their name.
create or replace function public.check_in_person_name(
  p_user_id uuid,
  p_circle_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(member.nickname), ''),
    nullif(btrim(p.display_name), ''),
    p.username,
    ''
  )
  from public.profiles p
  left join public.circle_members member
    on member.circle_id = p_circle_id and member.user_id = p.id
  where p.id = p_user_id;
$$;

revoke execute on function public.check_in_person_name(uuid, uuid)
  from public, anon, authenticated;

-- The circle a conversation's channel belongs to, or null.
create or replace function public.check_in_circle_of(p_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select cc.circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(p_conversation_id);
$$;

revoke execute on function public.check_in_circle_of(uuid)
  from public, anon, authenticated;

-- The short form of a board for the caller (a card): no lists.
create or replace function public.check_in_summary(b public.check_in_boards)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  today date := public.check_in_local_day(now(), b.time_zone);
  mine public.check_in_entries%rowtype;
  streak public.check_in_streaks%rowtype;
begin
  select * into mine
  from public.check_in_entries e
  where e.board_id = b.id and e.user_id = auth.uid() and e.day = today;
  select * into streak
  from public.check_in_streaks s
  where s.board_id = b.id and s.user_id = auth.uid();

  return jsonb_build_object(
    'id', b.id,
    'conversation_id', b.conversation_id,
    'message_id', b.message_id,
    'title', b.title,
    'description', b.description,
    'time_zone', b.time_zone,
    'remind_minute', b.remind_minute,
    'ends_on', b.ends_on,
    'today', today,
    'closed', public.check_in_is_closed(b),
    'closed_at', b.closed_at,
    'created_by', b.created_by,
    'created_at', b.created_at,
    'can_manage', public.check_in_can_manage(b),
    'today_count', (
      select count(*)::integer
      from public.check_in_entries e
      join public.conversation_members cm
        on cm.conversation_id = b.conversation_id and cm.user_id = e.user_id
      where e.board_id = b.id and e.day = today
    ),
    'member_total', public.check_in_member_total(b.conversation_id),
    'my_checked_in', mine.id is not null,
    'my_note', mine.note,
    'my_photo', case
      when mine.photo_path is null then null
      else jsonb_build_object(
        'bucket', 'chat-images', 'path', mine.photo_path, 'mime_type', mine.photo_mime
      )
    end,
    'my_streak', public.check_in_live_streak(streak.current_streak, streak.last_day, today),
    'my_best_streak', coalesce(streak.best_streak, 0),
    'my_total_days', coalesce(streak.total_days, 0)
  );
end;
$$;

revoke execute on function public.check_in_summary(public.check_in_boards)
  from public, anon, authenticated;

-- The check-ins of one day, in the order people checked in.
create or replace function public.check_in_day_entries(
  b public.check_in_boards,
  p_day date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(row_json order by created_at, id), '[]'::jsonb)
  from (
    select
      e.id,
      e.created_at,
      jsonb_build_object(
        'id', e.id,
        'user_id', e.user_id,
        'name', public.check_in_person_name(e.user_id, public.check_in_circle_of(b.conversation_id)),
        'avatar_url', coalesce(member.avatar_url, p.avatar_url),
        'day', e.day,
        'note', e.note,
        'photo', case
          when e.photo_path is null then null
          else jsonb_build_object(
            'bucket', 'chat-images', 'path', e.photo_path, 'mime_type', e.photo_mime
          )
        end,
        'streak', public.check_in_live_streak(
          s.current_streak, s.last_day, public.check_in_local_day(now(), b.time_zone)
        ),
        'created_at', e.created_at
      ) as row_json
    from public.check_in_entries e
    join public.conversation_members cm
      on cm.conversation_id = b.conversation_id and cm.user_id = e.user_id
    join public.profiles p on p.id = e.user_id
    left join public.circle_members member
      on member.circle_id = public.check_in_circle_of(b.conversation_id)
      and member.user_id = e.user_id
    left join public.check_in_streaks s
      on s.board_id = e.board_id and s.user_id = e.user_id
    where e.board_id = b.id
      and e.day = p_day
      and (e.user_id = auth.uid() or not public.are_users_blocked(auth.uid(), e.user_id))
    order by e.created_at, e.id
    limit 200
  ) q;
$$;

revoke execute on function public.check_in_day_entries(public.check_in_boards, date)
  from public, anon, authenticated;

-- ------------------------------------------------------------------ create

create or replace function public.create_check_in(
  target_conversation_id uuid,
  check_in_title text,
  check_in_description text default null,
  check_in_time_zone text default null,
  check_in_remind_minute integer default null,
  check_in_ends_on date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  clean_title text := btrim(coalesce(check_in_title, ''));
  clean_description text := btrim(coalesce(check_in_description, ''));
  zone text := public.check_in_clean_zone(check_in_time_zone);
  today date;
  new_board_id uuid := gen_random_uuid();
  new_message_id uuid;
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
  if not public.chain_conversation_allowed(target_conversation_id)
    or exists (
      select 1 from public.conversations c
      where c.id = target_conversation_id and c.type = 'thread'
    )
  then
    raise exception 'check_in_not_allowed' using errcode = '22023';
  end if;
  if not public.can_current_user_send_in_conversation(target_conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if char_length(clean_title) not between 1 and 120 then
    raise exception 'check_in_title_invalid' using errcode = '22023';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'check_in_text_too_long' using errcode = '22023';
  end if;
  if check_in_remind_minute is not null
    and check_in_remind_minute not between 0 and 1439
  then
    raise exception 'check_in_remind_invalid' using errcode = '22023';
  end if;
  today := public.check_in_local_day(now(), zone);
  if check_in_ends_on is not null
    and (check_in_ends_on < today or check_in_ends_on > today + 730)
  then
    raise exception 'check_in_end_invalid' using errcode = '22023';
  end if;
  if (
    select count(*) from public.check_in_boards b
    where b.conversation_id = target_conversation_id
      and b.closed_at is null
      and (b.ends_on is null or b.ends_on >= public.check_in_local_day(now(), b.time_zone))
  ) >= 5 then
    raise exception 'check_in_too_many' using errcode = 'P0001';
  end if;

  -- The free text of a member the AI guard would hold waits with the card:
  -- the card itself is a message and goes through the guard like any other,
  -- and the description is part of what it shows.
  if clean_description <> ''
    and public.chain_note_needs_review(target_conversation_id, uid)
  then
    clean_description := '';
  end if;

  insert into public.check_in_boards (
    id, conversation_id, created_by, title, description, time_zone,
    remind_minute, ends_on
  )
  values (
    new_board_id, target_conversation_id, uid, clean_title, clean_description,
    zone, check_in_remind_minute, check_in_ends_on
  );

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    uid,
    'text',
    E'✅ ' || clean_title,
    jsonb_build_object(
      'kind', 'check_in', 'check_in_id', new_board_id, 'title', clean_title
    )
  )
  returning id into new_message_id;

  update public.check_in_boards set message_id = new_message_id where id = new_board_id;

  return jsonb_build_object('check_in_id', new_board_id, 'message_id', new_message_id);
end;
$$;

-- ----------------------------------------------------------------- reading

create or replace function public.get_check_in(target_check_in_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b public.check_in_boards%rowtype;
  today date;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into b from public.check_in_boards where id = target_check_in_id;
  if b.id is null
    or not public.is_current_user_conversation_member(b.conversation_id)
    or not public.check_in_card_visible(b.message_id)
  then
    raise exception 'Check-in not found' using errcode = 'P0002';
  end if;
  today := public.check_in_local_day(now(), b.time_zone);

  result := public.check_in_summary(b);
  return result || jsonb_build_object(
    'entries', public.check_in_day_entries(b, today),
    'leaders', coalesce((
      select jsonb_agg(l.row_json order by l.run desc, l.name)
      from (
        select
          public.check_in_live_streak(s.current_streak, s.last_day, today) as run,
          public.check_in_person_name(s.user_id, public.check_in_circle_of(b.conversation_id)) as name,
          jsonb_build_object(
            'user_id', s.user_id,
            'name', public.check_in_person_name(s.user_id, public.check_in_circle_of(b.conversation_id)),
            'avatar_url', coalesce(member.avatar_url, p.avatar_url),
            'streak', public.check_in_live_streak(s.current_streak, s.last_day, today)
          ) as row_json
        from public.check_in_streaks s
        join public.conversation_members cm
          on cm.conversation_id = b.conversation_id and cm.user_id = s.user_id
        join public.profiles p on p.id = s.user_id and p.deleted_at is null
        left join public.circle_members member
          on member.circle_id = public.check_in_circle_of(b.conversation_id)
          and member.user_id = s.user_id
        where s.board_id = b.id
          and s.last_day >= today - 1
          and s.current_streak >= 2
          and (s.user_id = auth.uid() or not public.are_users_blocked(auth.uid(), s.user_id))
        order by s.current_streak desc, s.user_id
        limit 5
      ) l
    ), '[]'::jsonb),
    'my_days', coalesce((
      select jsonb_agg(e.day order by e.day)
      from public.check_in_entries e
      where e.board_id = b.id
        and e.user_id = auth.uid()
        and e.day >= today - 119
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_check_ins(target_check_in_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(public.check_in_summary(b)), '[]'::jsonb)
  into result
  from public.check_in_boards b
  where b.id = any (target_check_in_ids[1:50])
    and public.is_current_user_conversation_member(b.conversation_id)
    and public.check_in_card_visible(b.message_id);
  return result;
end;
$$;

create or replace function public.get_check_in_day(
  target_check_in_id uuid,
  target_day date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b public.check_in_boards%rowtype;
  today date;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into b from public.check_in_boards where id = target_check_in_id;
  if b.id is null
    or not public.is_current_user_conversation_member(b.conversation_id)
    or not public.check_in_card_visible(b.message_id)
  then
    raise exception 'Check-in not found' using errcode = 'P0002';
  end if;
  today := public.check_in_local_day(now(), b.time_zone);
  if target_day is null or target_day > today or target_day < today - 400 then
    raise exception 'check_in_day_invalid' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'day', target_day,
    'count', (
      select count(*)::integer
      from public.check_in_entries e
      join public.conversation_members cm
        on cm.conversation_id = b.conversation_id and cm.user_id = e.user_id
      where e.board_id = b.id and e.day = target_day
    ),
    'entries', public.check_in_day_entries(b, target_day)
  );
end;
$$;

-- ---------------------------------------------------------------- checking in

create or replace function public.submit_check_in(
  target_check_in_id uuid,
  entry_note text default '',
  entry_photo jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.check_in_boards%rowtype;
  today date;
  clean_note text := btrim(coalesce(entry_note, ''));
  held boolean := false;
  photo_path_clean text;
  photo_mime_clean text;
  was_update boolean;
  home_circle uuid;
  streak public.check_in_streaks%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into b from public.check_in_boards where id = target_check_in_id for update;
  if b.id is null
    or not public.is_current_user_conversation_member(b.conversation_id)
    or not public.check_in_card_visible(b.message_id)
  then
    raise exception 'Check-in not found' using errcode = 'P0002';
  end if;
  if public.is_user_suspended(uid) then
    raise exception 'Account suspended' using errcode = '42501';
  end if;
  if not public.can_current_user_send_in_conversation(b.conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(b.conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if public.check_in_is_closed(b) then
    raise exception 'check_in_closed' using errcode = 'P0001';
  end if;
  if char_length(clean_note) > 200 then
    raise exception 'check_in_text_too_long' using errcode = '22023';
  end if;

  if entry_photo is not null and jsonb_typeof(entry_photo) <> 'null' then
    photo_path_clean := entry_photo ->> 'path';
    if jsonb_typeof(entry_photo) <> 'object'
      or entry_photo ->> 'bucket' is distinct from 'chat-images'
      or photo_path_clean is null
      or photo_path_clean !~ (
        '^' || b.conversation_id::text || '/check-ins/' || b.id::text
        || '/[A-Za-z0-9._-]{1,120}$'
      )
      or not exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'chat-images'
          and o.name = photo_path_clean
          and (o.owner = uid or o.owner_id = uid::text)
      )
    then
      raise exception 'check_in_photo_invalid' using errcode = '22023';
    end if;
    if jsonb_typeof(entry_photo -> 'mime_type') = 'string'
      and char_length(entry_photo ->> 'mime_type') <= 100
    then
      photo_mime_clean := entry_photo ->> 'mime_type';
    end if;
  end if;

  if clean_note <> '' and public.chain_note_needs_review(b.conversation_id, uid) then
    clean_note := '';
    held := true;
  end if;

  today := public.check_in_local_day(now(), b.time_zone);
  was_update := exists (
    select 1 from public.check_in_entries e
    where e.board_id = b.id and e.user_id = uid and e.day = today
  );

  insert into public.check_in_entries as e (
    board_id, user_id, day, note, photo_path, photo_mime
  )
  values (b.id, uid, today, clean_note, photo_path_clean, photo_mime_clean)
  on conflict (board_id, user_id, day) do update
  set note = excluded.note,
      photo_path = excluded.photo_path,
      photo_mime = excluded.photo_mime,
      updated_at = clock_timestamp();

  -- A day of activity for the circle (C3/C7).
  home_circle := public.check_in_circle_of(b.conversation_id);
  if home_circle is not null
    and not exists (select 1 from public.profiles p where p.id = uid and p.is_bot)
    and exists (
      select 1 from public.circle_members m
      where m.circle_id = home_circle and m.user_id = uid
    )
  then
    insert into public.circle_member_daily (circle_id, day, user_id)
    values (home_circle, public.insights_today(), uid)
    on conflict do nothing;
  end if;

  select * into streak
  from public.check_in_streaks s
  where s.board_id = b.id and s.user_id = uid;

  return jsonb_build_object(
    'day', today,
    'updated', was_update,
    'note_held', held,
    'streak', coalesce(streak.current_streak, 0),
    'best_streak', coalesce(streak.best_streak, 0),
    'total_days', coalesce(streak.total_days, 0)
  );
end;
$$;

create or replace function public.undo_check_in(target_check_in_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  b public.check_in_boards%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into b from public.check_in_boards where id = target_check_in_id for update;
  if b.id is null
    or not public.is_current_user_conversation_member(b.conversation_id)
    or not public.check_in_card_visible(b.message_id)
  then
    raise exception 'Check-in not found' using errcode = 'P0002';
  end if;
  if public.check_in_is_closed(b) then
    raise exception 'check_in_closed' using errcode = 'P0001';
  end if;
  delete from public.check_in_entries e
  where e.board_id = b.id
    and e.user_id = uid
    and e.day = public.check_in_local_day(now(), b.time_zone);
end;
$$;

create or replace function public.set_check_in_closed(
  target_check_in_id uuid,
  closed boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.check_in_boards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into b from public.check_in_boards where id = target_check_in_id for update;
  if b.id is null or not public.is_current_user_conversation_member(b.conversation_id) then
    raise exception 'Check-in not found' using errcode = 'P0002';
  end if;
  if not public.check_in_can_manage(b) then
    raise exception 'Only the creator or a moderator can close a check-in'
      using errcode = '42501';
  end if;

  if closed then
    update public.check_in_boards
    set closed_at = coalesce(closed_at, now()), closed_by = auth.uid(), updated_at = now()
    where id = b.id;
  else
    update public.check_in_boards
    set closed_at = null,
        closed_by = null,
        ends_on = case
          when ends_on < public.check_in_local_day(now(), time_zone) then null
          else ends_on
        end,
        updated_at = now()
    where id = b.id;
  end if;
end;
$$;

revoke execute on function public.create_check_in(uuid, text, text, text, integer, date)
  from public, anon;
revoke execute on function public.get_check_in(uuid) from public, anon;
revoke execute on function public.get_check_ins(uuid[]) from public, anon;
revoke execute on function public.get_check_in_day(uuid, date) from public, anon;
revoke execute on function public.submit_check_in(uuid, text, jsonb) from public, anon;
revoke execute on function public.undo_check_in(uuid) from public, anon;
revoke execute on function public.set_check_in_closed(uuid, boolean) from public, anon;

grant execute on function public.create_check_in(uuid, text, text, text, integer, date)
  to authenticated;
grant execute on function public.get_check_in(uuid) to authenticated;
grant execute on function public.get_check_ins(uuid[]) to authenticated;
grant execute on function public.get_check_in_day(uuid, date) to authenticated;
grant execute on function public.submit_check_in(uuid, text, jsonb) to authenticated;
grant execute on function public.undo_check_in(uuid) to authenticated;
grant execute on function public.set_check_in_closed(uuid, boolean) to authenticated;
