-- Media channels and Q&A channels (roadmap C9), part 1 of 4: the two new
-- channel kinds and what they keep.
--
-- * circle_channels.kind takes 'media' and 'qa'. Both are forum-like: a
--   channel of either kind holds posts (threads of the channel's
--   conversation), not a chat. A media channel is a picture wall: every post
--   needs a picture (migration 202610270320). A Q&A channel is a forum where
--   the asker or a moderator marks a post solved and picks the answer
--   (migration 202610270310).
-- * circle_channel_kind_has_posts(kind) is the one place that says which
--   kinds hold posts: forum, media and qa.
-- * Everything that branched on `kind = 'forum'` / `kind <> 'forum'` now asks
--   that helper. Those functions are patched in place from their CURRENT
--   definition (pg_get_functiondef), not rewritten, so nothing a later
--   migration added to them is lost (the AI guard's review_state, the album
--   counts, the profile bio rule, AutoMod's quiet sends, the assistant's
--   answers, thread locks, and so on):
--     check_channel_message_send   a post channel's own conversation takes no
--                                  messages
--     create_thread                posts are made with create_forum_post only
--     create_forum_post, list_forum_posts, set_forum_post_tags,
--     pin_forum_post, forum_channel_for_management
--                                  tags, pins and posts work in all three
--     circle_alert_channel, circle_automod_act, save_circle_automod_rule
--                                  AutoMod alerts and its excluded-channel
--                                  list never name a post channel
--     create_circle_from_template  a template's media and Q&A channels keep
--                                  their tags
--     create_circle_channel        accepts the two new kinds
-- * conversation_threads gets solved_at / solved_by / solved_message_id. They
--   are written only by the RPCs of 202610270310 (the table has no write
--   policy for clients).
-- * qa_answer_notices: a push waiting for somebody whose answer was accepted
--   (or whose question a moderator marked solved). Closed to clients; claimed
--   once by scheduled-dispatch.
-- * Leaving a circle, or deleting an account, takes the person's waiting
--   pushes with it; a deleted account also stops being named as the one who
--   solved a post (the post stays solved).
--
-- Deploy the app before applying this: an app from before reads an unknown
-- channel kind as a text channel.

-- 1. The kinds.
do $$
declare
  kinds text[];
begin
  select coalesce(
    array(
      select distinct m[1]
      from pg_constraint c
      cross join lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z]+)''', 'g') as m
      where c.conrelid = 'public.circle_channels'::regclass
        and c.conname = 'circle_channels_kind_check'
    ),
    array[]::text[]
  )
  into kinds;

  kinds := kinds || array['text', 'voice', 'forum', 'stage', 'announcement', 'media', 'qa'];

  alter table public.circle_channels
    drop constraint if exists circle_channels_kind_check;
  execute format(
    'alter table public.circle_channels add constraint circle_channels_kind_check check (kind in (%s))',
    (
      select string_agg(quote_literal(k), ', ' order by k)
      from (select distinct unnest(kinds) as k) as distinct_kinds
    )
  );
end $$;

create or replace function public.circle_channel_kind_has_posts(channel_kind text)
returns boolean
language sql
immutable
parallel safe
set search_path = public
as $$
  select channel_kind in ('forum', 'media', 'qa');
$$;

grant execute on function public.circle_channel_kind_has_posts(text)
  to authenticated, service_role;

-- 2. What a solved post keeps.
alter table public.conversation_threads
  add column if not exists solved_at timestamptz,
  add column if not exists solved_by uuid references public.profiles(id) on delete set null,
  add column if not exists solved_message_id uuid references public.messages(id) on delete set null;

alter table public.conversation_threads
  drop constraint if exists conversation_threads_solved_answer;
alter table public.conversation_threads
  add constraint conversation_threads_solved_answer check (
    solved_message_id is null or solved_at is not null
  );

create index if not exists conversation_threads_solved_idx
  on public.conversation_threads (parent_conversation_id)
  where solved_at is not null;

-- 3. Pushes waiting for the person whose answer was accepted (or whose
-- question was marked solved by a moderator).
create table if not exists public.qa_answer_notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  thread_id uuid not null references public.conversation_threads(id) on delete cascade,
  kind text not null,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz,
  constraint qa_answer_notices_kind check (kind in ('answer_accepted', 'marked_solved'))
);

create index if not exists qa_answer_notices_unclaimed_idx
  on public.qa_answer_notices (created_at)
  where push_claimed_at is null;
create index if not exists qa_answer_notices_recent_idx
  on public.qa_answer_notices (user_id, thread_id, kind, created_at);

alter table public.qa_answer_notices enable row level security;
revoke all on public.qa_answer_notices from public, anon, authenticated;

-- 4. Leaving, and leaving WeCord.
create or replace function public.qa_forget_left_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.qa_answer_notices
  where circle_id = old.circle_id and user_id = old.user_id;
  return null;
end;
$$;

revoke execute on function public.qa_forget_left_member()
  from public, anon, authenticated;

drop trigger if exists circle_members_forget_qa_notices on public.circle_members;
create trigger circle_members_forget_qa_notices
  after delete on public.circle_members
  for each row execute function public.qa_forget_left_member();

-- Same pattern as profiles_erase_honors (202610270200): prepare_account_deletion
-- is not rewritten. The post stays solved; it just stops naming the person.
create or replace function public.erase_qa_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.qa_answer_notices where user_id = new.id;
  update public.conversation_threads
  set solved_by = null
  where solved_by = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_qa_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_qa on public.profiles;
create trigger profiles_erase_qa
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_qa_of_deleted_account();

-- 5. Patch every function that branched on the forum kind, from its current
-- definition. `x.kind <> 'forum'` / `kind_value <> 'forum'` become
-- `not circle_channel_kind_has_posts(...)`; `= 'forum'` loses the `not`. A
-- function that is missing is a mistake in this list; one with nothing to
-- patch (already done) is left.
do $patch$
declare
  function_name text;
  target record;
  found_any boolean;
  original text;
  patched text;
begin
  foreach function_name in array array[
    'check_channel_message_send',
    'circle_alert_channel',
    'circle_automod_act',
    'create_circle_from_template',
    'create_forum_post',
    'create_thread',
    'forum_channel_for_management',
    'list_forum_posts',
    'pin_forum_post',
    'save_circle_automod_rule',
    'set_forum_post_tags'
  ] loop
    found_any := false;
    for target in
      select p.oid
      from pg_proc p
      where p.pronamespace = 'public'::regnamespace
        and p.proname = function_name
    loop
      found_any := true;
      original := pg_get_functiondef(target.oid);
      patched := regexp_replace(
        original,
        E'(\\m\\w+\\.kind|\\mkind_value)\\s*<>\\s*''forum''',
        E'not public.circle_channel_kind_has_posts(\\1)',
        'g'
      );
      patched := regexp_replace(
        patched,
        E'(\\m\\w+\\.kind|\\mkind_value)\\s*=\\s*''forum''',
        E'public.circle_channel_kind_has_posts(\\1)',
        'g'
      );
      if patched ~ E'(kind|kind_value)\\s*(=|<>)\\s*''forum''' then
        raise exception 'Could not widen the forum check in %', function_name;
      end if;
      if patched = original then
        if original !~ 'circle_channel_kind_has_posts' then
          raise exception 'No forum check to widen in %', function_name;
        end if;
      else
        execute patched;
      end if;
    end loop;
    if not found_any then
      raise exception 'Function % does not exist', function_name;
    end if;
  end loop;
end;
$patch$;

-- create_circle_channel lists the kinds a client may ask for.
do $patch$
declare
  target record;
  found_any boolean := false;
  original text;
  patched text;
begin
  for target in
    select p.oid
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'create_circle_channel'
  loop
    found_any := true;
    original := pg_get_functiondef(target.oid);
    patched := replace(
      original,
      'channel_kind not in (''text'', ''forum'', ''voice'', ''stage'')',
      'channel_kind not in (''text'', ''forum'', ''voice'', ''stage'', ''media'', ''qa'')'
    );
    if patched = original then
      if original !~ '''media'', ''qa''' then
        raise exception 'create_circle_channel does not list its kinds as expected';
      end if;
    else
      execute patched;
    end if;
  end loop;
  if not found_any then
    raise exception 'create_circle_channel does not exist';
  end if;
end;
$patch$;
