-- Feedback and help (K7), part 1 of 4: the table, the private screenshot
-- bucket and the one way to send feedback.
--
-- * user_feedback: what a person wrote in Settings, Feedback and help. The
--   app adds its version and platform; it never adds anything from chats, and
--   there is nowhere to put it. A row goes with the account (on delete
--   cascade, and when an account is deleted the profile stays as "Deleted
--   User", so a trigger on profiles.deleted_at erases the person's feedback,
--   the replies and their notice states, as 202610220210 does for edit
--   history) and the screenshots with it (the delete-account function empties
--   the bucket's folder of the person).
-- * Nobody reads or writes the table through the API. A person sends feedback
--   with submit_feedback (below); platform admins read and answer it with the
--   admin functions of 202610240650.
-- * feedback-screenshots: a PRIVATE bucket. Objects are named
--   "<user id>/<uuid>.jpg|png|webp". A person writes and deletes only in their
--   own folder (at most 20 files there) and reads only their own; platform
--   admins read everyone's (to look at a report, through a signed link). No
--   other policy: no update, no listing across folders.
-- * submit_feedback: 5 messages an hour per person at most (PB429, the code
--   the report functions use for the same thing).

create table if not exists public.user_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  message text not null,
  app_version text not null default '',
  platform text not null default '',
  screenshot_path text,
  status text not null default 'open' check (status in ('open', 'closed')),
  replied_at timestamptz,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint user_feedback_message_length check (
    char_length(message) between 1 and 2000
  ),
  constraint user_feedback_version_length check (
    char_length(app_version) <= 40 and char_length(platform) <= 40
  ),
  constraint user_feedback_screenshot_in_own_folder check (
    screenshot_path is null
    or screenshot_path ~ ('^' || user_id::text || '/[0-9a-zA-Z_-]{1,64}\.(jpg|png|webp)$')
  )
);

create index if not exists user_feedback_user_idx
  on public.user_feedback (user_id, created_at desc);
create index if not exists user_feedback_status_idx
  on public.user_feedback (status, created_at desc);

alter table public.user_feedback enable row level security;
revoke all on public.user_feedback from public, anon, authenticated;

-- A reply (a notice, 202610240620) belongs to the feedback it answers.
alter table public.announcements
  drop constraint if exists announcements_feedback_id_fkey;
alter table public.announcements
  add constraint announcements_feedback_id_fkey
  foreign key (feedback_id) references public.user_feedback(id) on delete cascade;

-- ---------------------------------------------------------------------------
-- Screenshots: a private bucket
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'feedback-screenshots',
  'feedback-screenshots',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- How many screenshots the caller has in their folder. A function, because a
-- policy on storage.objects that counts storage.objects itself recurses.
create or replace function public.feedback_screenshot_count()
returns integer
language sql
stable
security definer
set search_path = public, storage
as $$
  select count(*)::integer
  from storage.objects o
  where o.bucket_id = 'feedback-screenshots'
    and o.name like auth.uid()::text || '/%';
$$;

revoke execute on function public.feedback_screenshot_count() from public, anon;
grant execute on function public.feedback_screenshot_count() to authenticated;

-- The caller's own folder, or any folder for a platform admin.
drop policy if exists feedback_screenshots_select on storage.objects;
create policy feedback_screenshots_select
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'feedback-screenshots'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_app_admin()
    )
  );

drop policy if exists feedback_screenshots_insert_owner on storage.objects;
create policy feedback_screenshots_insert_owner
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'feedback-screenshots'
    and (storage.foldername(name))[1] = auth.uid()::text
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-zA-Z_-]{1,64}\.(jpg|png|webp)$'
    and public.feedback_screenshot_count() < 20
  );

drop policy if exists feedback_screenshots_delete_owner on storage.objects;
create policy feedback_screenshots_delete_owner
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'feedback-screenshots'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- Sending feedback
-- ---------------------------------------------------------------------------

create or replace function public.submit_feedback(
  feedback_message text,
  client_platform text default '',
  client_version text default '',
  screenshot_object_path text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  uid uuid := auth.uid();
  clean_message text := btrim(coalesce(feedback_message, ''));
  clean_path text := nullif(btrim(coalesce(screenshot_object_path, '')), '');
  new_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if clean_message = '' then
    raise exception 'Write a few words first' using errcode = '22023';
  end if;
  if char_length(clean_message) > 2000 then
    raise exception 'That message is too long' using errcode = '22023';
  end if;
  if clean_path is not null and (
    clean_path !~ ('^' || uid::text || '/[0-9a-zA-Z_-]{1,64}\.(jpg|png|webp)$')
    or not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'feedback-screenshots'
        and o.name = clean_path
    )
  ) then
    raise exception 'That screenshot is not there' using errcode = '22023';
  end if;
  if (
    select count(*)
    from public.user_feedback f
    where f.user_id = uid
      and f.created_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception 'Too many feedback messages. Try again later.'
      using errcode = 'PB429';
  end if;

  insert into public.user_feedback (
    user_id, message, app_version, platform, screenshot_path
  )
  values (
    uid,
    clean_message,
    left(btrim(coalesce(client_version, '')), 40),
    left(btrim(coalesce(client_platform, '')), 40),
    clean_path
  )
  returning id into new_id;
  return new_id;
end;
$$;

revoke execute on function public.submit_feedback(text, text, text, text)
  from public, anon;
grant execute on function public.submit_feedback(text, text, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Deleting an account
-- ---------------------------------------------------------------------------

-- prepare_account_deletion (202610160017) keeps the profile as "Deleted
-- User", so the foreign keys never fire. When the account is marked deleted
-- this erases the person's feedback (and with it the replies), the notices
-- meant for them, their read and dismissed marks, and their place on any
-- flag's allow list. A trigger, so prepare_account_deletion stays as it is.
create or replace function public.erase_feedback_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.user_feedback f where f.user_id = new.id;
  delete from public.announcements a where a.audience_user_id = new.id;
  delete from public.announcement_states s where s.user_id = new.id;
  update public.feature_flags ff
  set allow_user_ids = array_remove(ff.allow_user_ids, new.id)
  where new.id = any (ff.allow_user_ids);
  return new;
end;
$$;

revoke execute on function public.erase_feedback_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_feedback on public.profiles;
create trigger profiles_erase_feedback
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_feedback_of_deleted_account();
