-- Edit history (roadmap A2, part 1 of 3): every earlier version of an edited
-- message is kept, so everyone who can see the message can see what it said
-- before. "Edited" in the chat opens the list.
--
-- * public.message_edits keeps the OLD version of a message: version 1 is the
--   text as first sent, version 2 the text after the first edit, and so on.
--   The current text stays in messages.body. edited_at is when that version
--   was written (the message's created_at for version 1, otherwise the time of
--   the edit that made it).
-- * A BEFORE UPDATE trigger on messages writes the row whenever body changes.
--   edit_message (three versions, plus the locking trigger
--   messages_review_lock_edit and AutoMod's edit trigger) is NOT redefined:
--   whatever changes a message's text, now or later, is recorded. A trigger
--   that raises later in the same statement rolls the row back with the edit.
-- * Who reads it: the policy asks the messages table itself, as the caller,
--   so exactly the people who can select the message can select its history
--   (membership, the disappearing-messages expiry and a message waiting for
--   the AI guard, see 202610170091). message_visible_to_current_user takes
--   the message's columns, not its id, and would only repeat that policy.
-- * The history goes with the message:
--     - recall, moderator delete, the AI guard's "remove" and the copies of a
--       recalled published message all set recalled_at, which the same
--       trigger answers by deleting the rows (and by not saving the blanked
--       body);
--     - purge_expired_messages (disappearing messages) deletes the message and
--       the foreign key deletes the rows;
--     - deleting an account or a conversation deletes the messages, and the
--       rows follow;
--     - view-once media is never text and cannot be edited; the trigger also
--       refuses to keep a history for it.
-- * Search keeps indexing only the latest text: sync_message_search_entry is
--   not touched.

create table if not exists public.message_edits (
  message_id uuid not null references public.messages(id) on delete cascade,
  version integer not null check (version >= 1),
  body text not null,
  mentions jsonb not null default '[]'::jsonb,
  edited_at timestamptz not null,
  primary key (message_id, version)
);

alter table public.message_edits enable row level security;
revoke all on public.message_edits from anon, authenticated;
grant select on public.message_edits to authenticated;

drop policy if exists message_edits_select on public.message_edits;
create policy message_edits_select
  on public.message_edits for select
  to authenticated
  using (
    exists (
      select 1 from public.messages m where m.id = message_edits.message_id
    )
  );

create or replace function public.record_message_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Deleted for everyone: what it used to say goes too, and the emptied body
  -- of the deletion is not a version.
  if new.recalled_at is not null then
    delete from public.message_edits e where e.message_id = old.id;
    return new;
  end if;

  if new.body is not distinct from old.body
    or old.recalled_at is not null
    or old.type is distinct from 'text'
    or new.type is distinct from 'text'
    or old.attachment->>'view_once' = 'true'
  then
    return new;
  end if;

  insert into public.message_edits (message_id, version, body, mentions, edited_at)
  values (
    old.id,
    coalesce(
      (select max(e.version) from public.message_edits e where e.message_id = old.id),
      0
    ) + 1,
    old.body,
    coalesce(old.mentions, '[]'::jsonb),
    coalesce(old.edited_at, old.created_at)
  );
  return new;
end;
$$;

revoke execute on function public.record_message_edit() from public, anon, authenticated;

-- Named so that it fires after AutoMod's edit trigger (messages_circle_
-- automod_edit) and before messages_review_lock_edit: a refused edit leaves no
-- history because the whole statement rolls back.
drop trigger if exists messages_edit_history on public.messages;
create trigger messages_edit_history
  before update of body, recalled_at on public.messages
  for each row execute function public.record_message_edit();

-- Deleting an account (prepare_account_deletion, 202610160017) hides the
-- person's profile ("Deleted User") but leaves their messages in other
-- people's chats. What they overwrote is theirs to take back: the earlier
-- versions of all their messages go when the account is marked deleted. (A
-- profile that is really removed takes its messages and their history with
-- it through the foreign keys.) A trigger, so prepare_account_deletion
-- stays as it is.
create or replace function public.erase_edit_history_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.message_edits e
  using public.messages m
  where m.id = e.message_id
    and m.sender_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_edit_history_of_deleted_account() from public, anon, authenticated;

drop trigger if exists profiles_erase_edit_history on public.profiles;
create trigger profiles_erase_edit_history
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_edit_history_of_deleted_account();
