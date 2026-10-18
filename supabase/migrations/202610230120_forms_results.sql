-- Forms and collection sheets (D1, part 3 of 3): the results, closing and
-- reopening, and "remind the people who have not filled it in".
--
-- * get_form_results(form): the answers, for the creator and (by the form's
--   `results` setting) for everyone after they submitted or for everyone.
--   Someone who may not read them gets form_results_hidden (42501).
--   - A form that is not anonymous lists each answer sheet with the person
--     (name, avatar) and the times. The creator also gets `unfilled`, the
--     members who have not answered (never the people who left or who are
--     blocked either way).
--   - An ANONYMOUS form lists the answers only: no user_id, no name, no
--     times, and in an order that does not follow the order of arrival (so
--     the creator cannot match the n-th sheet to the n-th person who
--     answered). `unfilled` is null: it would name the people who did.
--   Even for the creator the user_id of an anonymous response is not
--   returned by any function; the table lets nobody read other people's rows.
--   `people` names the people picked in "member" questions.
-- * set_form_closed(form, closed): the creator closes or reopens a form
--   (reopening drops a deadline that has passed, as a chain does).
-- * remind_form_unfilled(form): the creator's nudge to the members who have
--   not answered. It reuses the "Remind unread" notices (202610220320): each
--   one gets a read_reminder_notices row for the form's card (the
--   "Reminder" card in their notifications) and the push goes out through
--   the push Edge Function with {read_reminder_message_id: <card id>}, which
--   words it for each device. At most 3 reminders per form, 6 hours apart,
--   and 30 reminders a day per person (rate_limited). Anonymous forms may be
--   reminded too: the people reminded are not returned, only their number.
-- * list_read_reminder_notices (latest definition: 202610220320) gets one
--   change: a reminder for a form stays until the person answers (or the
--   form closes), however far they have read; reading the card does not
--   answer it. Every other rule of that function is as it was.

-- Members who have not answered [f] and could: no bots, nobody the creator
-- blocked or who blocked the creator, nobody who cannot view the channel.
create or replace function public.form_unfilled_user_ids(f public.forms)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select cm.user_id
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = f.conversation_id
    and cm.user_id <> f.creator_id
    and not coalesce(p.is_bot, false)
    and not exists (
      select 1
      from public.form_responses r
      where r.form_id = f.id and r.user_id = cm.user_id
    )
    and not public.are_users_blocked(f.creator_id, cm.user_id)
    and public.form_user_can_view(f.conversation_id, cm.user_id);
$$;

revoke execute on function public.form_unfilled_user_ids(public.forms)
  from public, anon, authenticated;

create or replace function public.get_form_results(target_form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  f public.forms%rowtype;
  anonymous boolean;
  channel_circle_id uuid;
  responses jsonb;
  people jsonb;
  unfilled jsonb := null;
  total integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into f from public.forms where id = target_form_id;
  if f.id is null
    or not public.is_current_user_conversation_member(f.conversation_id)
    or not public.form_card_visible(f.message_id)
  then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;
  if not public.form_can_view_results(f) then
    raise exception 'form_results_hidden' using errcode = '42501';
  end if;

  anonymous := coalesce((f.settings->>'anonymous')::boolean, false);
  select cc.circle_id into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(f.conversation_id);

  if anonymous then
    select coalesce(jsonb_agg(
      jsonb_build_object('id', r.id, 'answers', r.answers)
      order by md5(r.id::text)
    ), '[]'::jsonb)
    into responses
    from public.form_responses r
    where r.form_id = f.id;
  else
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'user_id', r.user_id,
        'answers', r.answers,
        'submitted_at', r.submitted_at,
        'updated_at', r.updated_at
      )
      order by r.submitted_at, r.id
    ), '[]'::jsonb)
    into responses
    from public.form_responses r
    where r.form_id = f.id;
  end if;

  -- The people who appear: those who answered (not anonymous) and those
  -- picked in a member question.
  select coalesce(jsonb_object_agg(
    p.id,
    jsonb_build_object(
      'name', coalesce(
        nullif(btrim(m.nickname), ''),
        nullif(btrim(p.display_name), ''),
        p.username,
        ''
      ),
      'avatar_url', coalesce(m.avatar_url, p.avatar_url)
    )
  ), '{}'::jsonb)
  into people
  from public.profiles p
  left join public.circle_members m
    on m.circle_id = channel_circle_id and m.user_id = p.id
  where p.id in (
      select (r.answers->>(fld->>'id'))::uuid
      from public.form_responses r
      cross join lateral jsonb_array_elements(f.fields) fld
      where r.form_id = f.id
        and fld->>'type' = 'member'
        and r.answers ? (fld->>'id')
    )
    or (
      not anonymous
      and p.id in (select r.user_id from public.form_responses r where r.form_id = f.id)
    );

  if not anonymous and f.creator_id = auth.uid() then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'user_id', p.id,
        'name', coalesce(
          nullif(btrim(m.nickname), ''),
          nullif(btrim(p.display_name), ''),
          p.username,
          ''
        ),
        'avatar_url', coalesce(m.avatar_url, p.avatar_url)
      )
      order by lower(coalesce(nullif(btrim(p.display_name), ''), p.username)), p.id
    ), '[]'::jsonb)
    into unfilled
    from public.form_unfilled_user_ids(f) u
    join public.profiles p on p.id = u
    left join public.circle_members m
      on m.circle_id = channel_circle_id and m.user_id = p.id;
  end if;

  select count(*)::integer into total
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  where cm.conversation_id = f.conversation_id
    and not coalesce(p.is_bot, false);

  return jsonb_build_object(
    'form_id', f.id,
    'anonymous', anonymous,
    'responses', responses,
    'people', people,
    'unfilled', unfilled,
    'member_total', total
  );
end;
$$;

create or replace function public.set_form_closed(
  target_form_id uuid,
  closed boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  f public.forms%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into f from public.forms where id = target_form_id for update;
  if f.id is null
    or not public.is_current_user_conversation_member(f.conversation_id)
    or not public.form_card_visible(f.message_id)
  then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;
  if f.creator_id <> auth.uid() then
    raise exception 'Only the creator can close a form' using errcode = '42501';
  end if;

  if closed then
    update public.forms
    set closed_at = coalesce(closed_at, now()), closed_by = auth.uid(), updated_at = now()
    where id = f.id;
  else
    update public.forms
    set closed_at = null,
        closed_by = null,
        settings = case
          when nullif(settings->>'deadline', '') is not null
            and (settings->>'deadline')::timestamptz <= now()
          then settings - 'deadline'
          else settings
        end,
        updated_at = now()
    where id = f.id;
  end if;
end;
$$;

create table if not exists public.form_reminders (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references public.forms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_count integer not null check (recipient_count > 0),
  created_at timestamptz not null default now()
);

create index if not exists form_reminders_form_idx
  on public.form_reminders (form_id, created_at desc);
create index if not exists form_reminders_sender_idx
  on public.form_reminders (sender_id, created_at);

alter table public.form_reminders enable row level security;
revoke all on public.form_reminders from anon, authenticated;

create or replace function public.remind_form_unfilled(target_form_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  f public.forms%rowtype;
  recipients uuid[];
  sent_before integer;
  last_sent timestamptz;
  sent_today integer;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into f from public.forms where id = target_form_id for update;
  if f.id is null
    or not public.is_current_user_conversation_member(f.conversation_id)
    or not public.form_card_visible(f.message_id)
  then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;
  if f.creator_id <> uid then
    raise exception 'Only the creator can remind people' using errcode = '42501';
  end if;
  if public.form_is_closed(f) then
    raise exception 'form_closed' using errcode = 'P0001';
  end if;
  if f.message_id is null then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;

  select count(*)::integer, max(r.created_at)
  into sent_before, last_sent
  from public.form_reminders r
  where r.form_id = f.id;
  if sent_before >= 3 then
    raise exception 'remind_limit' using errcode = 'P0001';
  end if;
  if last_sent is not null and last_sent > now() - interval '6 hours' then
    raise exception 'remind_too_soon' using errcode = 'P0001';
  end if;

  select count(*)::integer into sent_today
  from public.form_reminders r
  where r.sender_id = uid and r.created_at > now() - interval '1 day';
  if sent_today >= 30 then
    raise exception 'rate_limited' using errcode = '53400';
  end if;

  select coalesce(array_agg(u), array[]::uuid[])
  into recipients
  from public.form_unfilled_user_ids(f) u;
  if cardinality(recipients) = 0 then
    raise exception 'nobody_to_remind' using errcode = 'P0001';
  end if;

  insert into public.form_reminders (form_id, sender_id, recipient_count)
  values (f.id, uid, cardinality(recipients));

  insert into public.read_reminder_notices (
    message_id, conversation_id, sender_id, recipient_id
  )
  select f.message_id, f.conversation_id, uid, r
  from unnest(recipients) as r
  on conflict (message_id, recipient_id) do update
  set created_at = now(), pushed_at = null, read_at = null;

  return cardinality(recipients);
end;
$$;

-- Whether a reminder for [card_message_id] is still wanted by [p_user_id]:
-- null when the message is no form card, 'awaiting' while the form is open
-- and they have not answered, 'done' otherwise.
create or replace function public.form_reminder_state(
  card_message_id uuid,
  p_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when f.id is null then null
    when public.form_is_closed(f) then 'done'
    when exists (
      select 1 from public.form_responses r
      where r.form_id = f.id and r.user_id = p_user_id
    ) then 'done'
    else 'awaiting'
  end
  from (select 1) one
  left join public.forms f on f.message_id = card_message_id;
$$;

revoke execute on function public.form_reminder_state(uuid, uuid)
  from public, anon, authenticated;

-- 202610220320, with the form change described at the top.
create or replace function public.list_read_reminder_notices(p_limit integer default 50)
returns table (
  notice_id uuid,
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_display_name text,
  sender_avatar_url text,
  body text,
  type text,
  message_created_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    n.id,
    n.message_id,
    n.conversation_id,
    n.sender_id,
    coalesce(nullif(btrim(ca.alias), ''), p.display_name),
    p.avatar_url,
    left(btrim(coalesce(m.body, '')), 200),
    m.type,
    m.created_at,
    n.created_at
  from public.read_reminder_notices n
  join public.messages m on m.id = n.message_id
  join public.profiles p on p.id = n.sender_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid() and ca.friend_id = n.sender_id
  where n.recipient_id = auth.uid()
    and auth.uid() is not null
    and n.read_at is null
    and n.created_at > now() - interval '30 days'
    and m.recalled_at is null
    and (m.expires_at is null or m.expires_at > now())
    and public.message_visible_to_current_user(
      m.review_state, m.sender_id, m.conversation_id
    )
    and exists (
      select 1
      from public.conversation_members me
      where me.conversation_id = n.conversation_id
        and me.user_id = auth.uid()
    )
    and not public.are_users_blocked(auth.uid(), n.sender_id)
    -- Reading the message answers the reminder; for a form it is answering
    -- the form that does.
    and case public.form_reminder_state(n.message_id, auth.uid())
      when 'awaiting' then true
      when 'done' then false
      else not exists (
        select 1
        from public.conversation_members me
        join public.messages read_message on read_message.id = me.last_read_message_id
        where me.conversation_id = n.conversation_id
          and me.user_id = auth.uid()
          and read_message.created_at >= m.created_at
      )
    end
  order by n.created_at desc, n.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
$$;

revoke execute on function public.get_form_results(uuid) from public, anon;
revoke execute on function public.set_form_closed(uuid, boolean) from public, anon;
revoke execute on function public.remind_form_unfilled(uuid) from public, anon;
revoke execute on function public.list_read_reminder_notices(integer) from public, anon;

grant execute on function public.get_form_results(uuid) to authenticated;
grant execute on function public.set_form_closed(uuid, boolean) to authenticated;
grant execute on function public.remind_form_unfilled(uuid) to authenticated;
grant execute on function public.list_read_reminder_notices(integer) to authenticated;
