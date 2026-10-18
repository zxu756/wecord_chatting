-- Edit history (roadmap A2, part 2 of 3): an edit goes back through the AI
-- guard while its author is still a new member.
--
-- Until now the guard looked at a message once, when it was sent; a new
-- member could send something harmless, wait for it to be released and then
-- edit it into spam. The same rules that decided at insert time
-- (messages_review_guard, 202610170090) decide again when the text changes:
-- the guard is on, the circle's AI switch is on, the sender is a member who
-- is not a bot, a moderator or a manager, and still counts as new. Then the
-- message is 'checking' again, exactly as at insert, and the same machinery
-- takes over: the `ai` function is woken the moment the edit is stored,
-- run_ai_guard_sweep (wecord-ai-guard-sweep) releases it as not checked when
-- the answer never comes, a moderator decides in the Review queue when the
-- AI flags it. AutoMod already checks edits (messages_circle_automod_edit).
--
-- Nothing in the guard is redefined; three triggers sit beside it:
--  * messages_review_recheck_edit (BEFORE UPDATE OF body on messages) puts
--    the message back to 'checking'. It sorts after messages_review_lock_edit
--    on purpose: a message that is already waiting cannot be edited, and the
--    lock looks at the state before this trigger changes it.
--  * messages_review_recheck_open (AFTER UPDATE) resets the message's
--    message_reviews row (one per message) and wakes the function, or
--    releases the message as not checked when nothing can be woken, like
--    messages_review_open does for a new message.
--  * Two details of a release only make sense for a new message, so for an
--    edit review they are undone by triggers: the message keeps its place in
--    the chat (ai_guard_release_message moves a message that waited to the
--    end) and nobody is pushed (an edit never was). message_reviews.after_edit
--    marks those reviews.
-- While the check runs the whole message is hidden from everyone but its
-- author and the moderators, as a new message is; it comes back with its new
-- text when it is released. A moderator who removes it removes the message.

alter table public.message_reviews
  add column if not exists after_edit boolean not null default false;

create or replace function public.messages_review_recheck_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  guard public.circle_ai_guard%rowtype;
  joined_at timestamptz;
  is_new boolean;
begin
  if new.body is not distinct from old.body
    or old.review_state is not null
    or new.recalled_at is not null
    or new.type <> 'text'
    or btrim(coalesce(new.body, '')) = ''
    or new.webhook_id is not null
    or new.webhook_name is not null
    -- A copy of a published message follows its source; the source is the
    -- one that is checked.
    or new.crosspost is not null
  then
    return new;
  end if;

  -- Only the author's own edit: the guard is about what a new member says.
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

  select g.* into guard
  from public.circle_ai_guard g
  where g.circle_id = channel_circle_id and g.enabled;
  if guard.circle_id is null then
    return new;
  end if;

  if not exists (
    select 1 from public.circles c where c.id = channel_circle_id and c.ai_enabled
  ) then
    return new;
  end if;

  select cm.created_at into joined_at
  from public.circle_members cm
  where cm.circle_id = channel_circle_id and cm.user_id = new.sender_id;
  if joined_at is null then
    return new;
  end if;

  if exists (select 1 from public.profiles p where p.id = new.sender_id and p.is_bot)
    or public.circle_member_has_permission(channel_circle_id, new.sender_id, 'manage_messages')
    or public.circle_member_has_permission(channel_circle_id, new.sender_id, 'manage_circle')
  then
    return new;
  end if;

  if guard.new_rule = 'joined_days' then
    is_new := joined_at > now() - make_interval(days => guard.joined_days);
  else
    -- As at insert time, counting the visible messages the sender has in the
    -- circle, except this one (when it was sent it was not counted yet).
    is_new := (
      select count(*)
      from (
        select 1
        from public.messages m
        where m.sender_id = new.sender_id
          and m.id <> new.id
          and m.recalled_at is null
          and m.review_state is null
          and m.conversation_id in (
            select cc.conversation_id
            from public.circle_channels cc
            where cc.circle_id = channel_circle_id
            union all
            select ct.conversation_id
            from public.conversation_threads ct
            join public.circle_channels cc
              on cc.conversation_id = ct.parent_conversation_id
            where cc.circle_id = channel_circle_id
          )
        limit guard.message_count
      ) counted
    ) < guard.message_count;
  end if;

  if is_new then
    new.review_state := 'checking';
  end if;
  return new;
end;
$$;

create or replace function public.messages_review_recheck_open()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel_circle_id uuid;
  guard_mode text;
begin
  select cc.circle_id
  into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(new.conversation_id);

  select g.action into guard_mode
  from public.circle_ai_guard g
  where g.circle_id = channel_circle_id;

  insert into public.message_reviews as r (
    message_id, circle_id, conversation_id, sender_id, mode, after_edit
  )
  values (
    new.id, channel_circle_id, new.conversation_id, new.sender_id,
    coalesce(guard_mode, 'hold'), true
  )
  on conflict (message_id) do update
  set mode = excluded.mode,
    state = 'checking',
    verdict = null,
    reason = null,
    reason_zh = null,
    unchecked_reason = null,
    created_at = now(),
    check_started_at = null,
    checked_at = null,
    released_at = null,
    decided_at = null,
    decided_by = null,
    push_pending = false,
    after_edit = true;

  if not public.ai_guard_wake(
    'ai',
    jsonb_build_object('action', 'guard', 'message_id', new.id)
  ) then
    perform public.finish_message_review(new.id, 'not_checked', null, 'unavailable');
  end if;
  return null;
end;
$$;

-- A reviewed edit is not a new message: nobody is pushed for it.
create or replace function public.message_reviews_no_push_after_edit()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.after_edit then
    new.push_pending := false;
  end if;
  return new;
end;
$$;

-- ... and it keeps its place in the chat when it is released (by the AI or
-- by a moderator).
create or replace function public.messages_keep_place_after_edit_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.review_state is not null
    and new.review_state is null
    and new.created_at is distinct from old.created_at
    and exists (
      select 1
      from public.message_reviews r
      where r.message_id = new.id and r.after_edit
    )
  then
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_review_recheck_edit() from public, anon, authenticated;
revoke execute on function public.messages_review_recheck_open() from public, anon, authenticated;
revoke execute on function public.message_reviews_no_push_after_edit() from public, anon, authenticated;
revoke execute on function public.messages_keep_place_after_edit_review() from public, anon, authenticated;

drop trigger if exists messages_review_recheck_edit on public.messages;
create trigger messages_review_recheck_edit
  before update of body on public.messages
  for each row execute function public.messages_review_recheck_edit();

drop trigger if exists messages_review_recheck_open on public.messages;
create trigger messages_review_recheck_open
  after update of body on public.messages
  for each row
  when (
    old.review_state is null
    and new.review_state = 'checking'
    and new.body is distinct from old.body
  )
  execute function public.messages_review_recheck_open();

drop trigger if exists message_reviews_no_push_after_edit on public.message_reviews;
create trigger message_reviews_no_push_after_edit
  before insert or update on public.message_reviews
  for each row execute function public.message_reviews_no_push_after_edit();

drop trigger if exists messages_keep_place_after_edit_review on public.messages;
create trigger messages_keep_place_after_edit_review
  before update of review_state on public.messages
  for each row execute function public.messages_keep_place_after_edit_review();
