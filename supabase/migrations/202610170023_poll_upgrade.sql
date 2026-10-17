-- Polls upgrade: quizzes, anonymous votes, a deadline you pick, and options
-- added by members.
--
-- * Quiz: one option is right and the author may explain why. The answer
--   lives in poll_quiz_answers, which clients cannot read; poll_results
--   shows it ({correct, explanation}) to someone who has voted, to the
--   author, and to everyone once the poll has closed. A quiz takes one
--   answer, and an answer cannot be changed or withdrawn.
-- * Anonymous: attachment.anonymous = true. Counts show; who voted does
--   not: list_poll_voters returns nobody and members cannot read other
--   people's vote rows (the select policy only shows them their own).
-- * Deadline: create_poll takes closes_at (up to 30 days ahead) besides
--   duration_hours; closes_at wins.
-- * Members add options: attachment.allow_add = true lets any member who
--   can vote add an option (add_poll_option), up to 10 options in all,
--   never in a quiz.
-- * create_poll keeps working with its five old arguments.

create table if not exists public.poll_quiz_answers (
  message_id uuid primary key references public.messages(id) on delete cascade,
  correct_option_id text not null,
  explanation text,
  constraint poll_quiz_answers_explanation_length
    check (explanation is null or char_length(explanation) between 1 and 500)
);

alter table public.poll_quiz_answers enable row level security;
revoke all on public.poll_quiz_answers from anon, authenticated;

-- Votes of anonymous polls are private to the voter.
drop policy if exists message_poll_votes_select_member on public.message_poll_votes;
create policy message_poll_votes_select_member
  on public.message_poll_votes for select
  to authenticated
  using (
    conversation_id in (select public.current_user_readable_conversation_ids())
    and (
      user_id = auth.uid()
      or not exists (
        select 1
        from public.messages m
        where m.id = message_poll_votes.message_id
          and m.attachment->>'anonymous' = 'true'
      )
    )
  );

drop function if exists public.create_poll(uuid, text, text[], boolean, integer);

create or replace function public.create_poll(
  target_conversation_id uuid,
  question text,
  options text[],
  multi boolean default false,
  duration_hours integer default null,
  quiz_correct_option integer default null,
  quiz_explanation text default null,
  anonymous boolean default false,
  allow_add_options boolean default false,
  closes_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_question text := btrim(coalesce(question, ''));
  trimmed_explanation text := nullif(btrim(coalesce(quiz_explanation, '')), '');
  trimmed_options text[];
  option_count integer;
  poll_options jsonb;
  poll_ends_at timestamptz;
  is_quiz boolean := quiz_correct_option is not null;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_question) not between 1 and 300 then
    raise exception 'Poll question must be 1 to 300 characters'
      using errcode = '22023';
  end if;

  select array_agg(btrim(coalesce(item.option_text, '')) order by item.ordinality)
  into trimmed_options
  from unnest(coalesce(options, array[]::text[]))
    with ordinality as item(option_text, ordinality);

  option_count := coalesce(cardinality(trimmed_options), 0);
  if option_count not between 2 and 10 then
    raise exception 'A poll needs 2 to 10 options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(trimmed_options) as item(option_text)
    where char_length(item.option_text) not between 1 and 100
  ) then
    raise exception 'Poll options must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  if (
    select count(distinct lower(item.option_text))
    from unnest(trimmed_options) as item(option_text)
  ) <> option_count then
    raise exception 'Poll options must be different' using errcode = '22023';
  end if;

  if duration_hours is not null and duration_hours not between 1 and 168 then
    raise exception 'Poll duration must be 1 to 168 hours'
      using errcode = '22023';
  end if;

  if closes_at is not null
    and (closes_at < now() + interval '1 minute'
      or closes_at > now() + interval '30 days')
  then
    raise exception 'A poll can close between a minute and 30 days from now'
      using errcode = '22023';
  end if;

  if is_quiz then
    if quiz_correct_option not between 1 and option_count then
      raise exception 'Choose which answer is right' using errcode = '22023';
    end if;
    if coalesce(multi, false) then
      raise exception 'A quiz has one right answer' using errcode = '22023';
    end if;
    if coalesce(allow_add_options, false) then
      raise exception 'Nobody can add answers to a quiz' using errcode = '22023';
    end if;
    if trimmed_explanation is not null
      and char_length(trimmed_explanation) > 500
    then
      raise exception 'The explanation can be up to 500 characters'
        using errcode = '22023';
    end if;
  else
    trimmed_explanation := null;
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  select jsonb_agg(
    jsonb_build_object('id', 'o' || item.ordinality, 'text', item.option_text)
    order by item.ordinality
  )
  into poll_options
  from unnest(trimmed_options) with ordinality as item(option_text, ordinality);

  if closes_at is not null then
    poll_ends_at := closes_at;
  elsif duration_hours is not null then
    poll_ends_at := now() + make_interval(hours => duration_hours);
  end if;

  -- AutoMod (202610160035): a blocked message is dropped, not raised.
  perform set_config('wecord.automod_soft', 'on', true);

  -- The send trigger checks send_messages and slowmode in circle channels.
  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'poll',
    trimmed_question,
    jsonb_build_object(
      'kind', 'poll',
      'question', trimmed_question,
      'options', poll_options,
      'multi', coalesce(multi, false),
      'ends_at', poll_ends_at,
      'quiz', is_quiz,
      'anonymous', coalesce(anonymous, false),
      'allow_add', coalesce(allow_add_options, false)
    )
  )
  returning id into created_message_id;

  perform set_config('wecord.automod_soft', 'off', true);

  if created_message_id is not null and is_quiz then
    insert into public.poll_quiz_answers (message_id, correct_option_id, explanation)
    values (created_message_id, 'o' || quiz_correct_option, trimmed_explanation);
  end if;

  return created_message_id;
end;
$$;

revoke execute on function public.create_poll(uuid, text, text[], boolean, integer, integer, text, boolean, boolean, timestamptz) from public, anon;
grant execute on function public.create_poll(uuid, text, text[], boolean, integer, integer, text, boolean, boolean, timestamptz) to authenticated;

-- Same as 202610130023_polls, but a quiz answer is final.
create or replace function public.vote_poll(
  target_message_id uuid,
  option_ids text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  poll public.messages%rowtype;
  chosen text[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  -- Shares the row with other voters; end_poll waits for them.
  select m.*
  into poll
  from public.messages m
  where m.id = target_message_id
    and m.type = 'poll'
  for share;

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
  then
    raise exception 'Poll not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.poll_is_closed(poll) then
    raise exception 'This poll has ended' using errcode = '22023';
  end if;

  if public.is_current_user_blocked_in_conversation(poll.conversation_id) then
    raise exception 'Cannot vote in this conversation' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct btrim(item.option_id)), array[]::text[])
  into chosen
  from unnest(coalesce(option_ids, array[]::text[])) as item(option_id)
  where item.option_id is not null;

  if exists (
    select 1
    from unnest(chosen) as item(option_id)
    where not exists (
      select 1
      from jsonb_array_elements(poll.attachment->'options') o
      where o->>'id' = item.option_id
    )
  ) then
    raise exception 'Unknown poll option' using errcode = '22023';
  end if;

  if cardinality(chosen) > 1
    and not coalesce((poll.attachment->>'multi')::boolean, false)
  then
    raise exception 'This poll takes one answer' using errcode = '22023';
  end if;

  if coalesce((poll.attachment->>'quiz')::boolean, false) then
    if cardinality(chosen) <> 1 then
      raise exception 'Pick an answer' using errcode = '22023';
    end if;
    if exists (
      select 1
      from public.message_poll_votes v
      where v.message_id = poll.id and v.user_id = current_user_id
    ) then
      raise exception 'A quiz answer cannot be changed' using errcode = '22023';
    end if;
  end if;

  delete from public.message_poll_votes v
  where v.message_id = poll.id
    and v.user_id = current_user_id
    and not (v.option_id = any(chosen));

  insert into public.message_poll_votes (
    message_id,
    user_id,
    option_id,
    conversation_id
  )
  select poll.id, current_user_id, item.option_id, poll.conversation_id
  from unnest(chosen) as item(option_id)
  on conflict do nothing;
end;
$$;

-- A member adds an option to a poll that allows it.
create or replace function public.add_poll_option(
  target_message_id uuid,
  option_text text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  poll public.messages%rowtype;
  trimmed text := btrim(coalesce(option_text, ''));
  option_count integer;
  next_number integer;
  new_id text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed) not between 1 and 100 then
    raise exception 'Poll options must be 1 to 100 characters'
      using errcode = '22023';
  end if;

  select m.*
  into poll
  from public.messages m
  where m.id = target_message_id
    and m.type = 'poll'
  for update;

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
  then
    raise exception 'Poll not found or caller is not a member'
      using errcode = '42501';
  end if;

  if not coalesce((poll.attachment->>'allow_add')::boolean, false) then
    raise exception 'This poll does not take new options' using errcode = '22023';
  end if;

  if public.poll_is_closed(poll) then
    raise exception 'This poll has ended' using errcode = '22023';
  end if;

  if public.is_current_user_blocked_in_conversation(poll.conversation_id) then
    raise exception 'Cannot vote in this conversation' using errcode = '42501';
  end if;

  select
    count(*),
    coalesce(max(substr(o->>'id', 2)::integer), 0) + 1
  into option_count, next_number
  from jsonb_array_elements(poll.attachment->'options') o;

  if option_count >= 10 then
    raise exception 'A poll can have up to 10 options' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(poll.attachment->'options') o
    where lower(o->>'text') = lower(trimmed)
  ) then
    raise exception 'Poll options must be different' using errcode = '22023';
  end if;

  new_id := 'o' || next_number;

  update public.messages m
  set attachment = jsonb_set(
    m.attachment,
    '{options}',
    (m.attachment->'options') || jsonb_build_array(
      jsonb_build_object('id', new_id, 'text', trimmed, 'added_by', current_user_id)
    )
  )
  where m.id = poll.id;

  return new_id;
end;
$$;

revoke execute on function public.add_poll_option(uuid, text) from public, anon;
grant execute on function public.add_poll_option(uuid, text) to authenticated;

-- Same as 202610130023_polls, plus the quiz answer for those who may see
-- it ({correct, explanation}); null before.
create or replace function public.poll_results(message_row public.messages)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  poll public.messages%rowtype;
  vote_counts jsonb;
  voter_count integer;
  mine jsonb;
  is_closed boolean;
  answer public.poll_quiz_answers%rowtype;
  reveal boolean;
begin
  if message_row.type is distinct from 'poll' then
    return null;
  end if;

  -- The stored message, not the row passed in, decides what is shown.
  select m.*
  into poll
  from public.messages m
  where m.id = message_row.id
    and m.type = 'poll';

  if poll.id is null
    or not public.is_current_user_conversation_member(poll.conversation_id)
  then
    return null;
  end if;

  select
    coalesce(
      jsonb_object_agg(counted.option_id, counted.vote_count),
      '{}'::jsonb
    )
  into vote_counts
  from (
    select v.option_id, count(*)::integer as vote_count
    from public.message_poll_votes v
    where v.message_id = poll.id
    group by v.option_id
  ) counted;

  select count(distinct v.user_id)::integer
  into voter_count
  from public.message_poll_votes v
  where v.message_id = poll.id;

  select coalesce(jsonb_agg(v.option_id order by v.option_id), '[]'::jsonb)
  into mine
  from public.message_poll_votes v
  where v.message_id = poll.id
    and v.user_id = auth.uid();

  is_closed := public.poll_is_closed(poll);

  if coalesce((poll.attachment->>'quiz')::boolean, false) then
    select a.* into answer
    from public.poll_quiz_answers a
    where a.message_id = poll.id;
    reveal := is_closed
      or poll.sender_id = auth.uid()
      or jsonb_array_length(mine) > 0;
  end if;

  return jsonb_build_object(
    'counts', vote_counts,
    'total_voters', voter_count,
    'my_votes', mine,
    'closed', is_closed
  ) || case
    when reveal and answer.message_id is not null then jsonb_build_object(
      'correct', answer.correct_option_id,
      'explanation', answer.explanation
    )
    else '{}'::jsonb
  end;
end;
$$;

-- Same as 202610130023_polls, but an anonymous poll has no voter list.
create or replace function public.list_poll_voters(
  target_message_id uuid,
  target_option_id text
)
returns table (
  id uuid,
  username text,
  display_name text,
  avatar_url text,
  bio text,
  created_at timestamptz,
  updated_at timestamptz,
  alias text,
  voted_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.username,
    p.display_name,
    p.avatar_url,
    p.bio,
    p.created_at,
    p.updated_at,
    ca.alias,
    v.created_at as voted_at
  from public.message_poll_votes v
  join public.messages m on m.id = v.message_id
  join public.profiles p on p.id = v.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  where auth.uid() is not null
    and v.message_id = target_message_id
    and v.option_id = target_option_id
    and m.type = 'poll'
    and m.recalled_at is null
    and coalesce(m.attachment->>'anonymous', 'false') <> 'true'
    and public.is_current_user_conversation_member(m.conversation_id)
  order by v.created_at, p.id;
$$;
