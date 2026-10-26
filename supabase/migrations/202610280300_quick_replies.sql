-- Quick replies (roadmap A8, part 1 of 4): phrases a person keeps to send with
-- a slash.
--
-- * quick_replies: one row per phrase, owner only. The shortcut is what is
--   typed after the "/" in the message box (lower case, no spaces, no slash,
--   at most 32 characters). It is not for the database to forbid a built-in
--   command's name: the app lists quick replies first and a built-in command
--   with the same name still works when typed in full. The body is what is
--   put in the message box, at most 2000 characters. A person keeps at most
--   50.
-- * A trigger tidies the row (shortcut lower-cased and trimmed, body trimmed,
--   the owner and creation time kept on update) and enforces the limit with a
--   lock per person, so two devices adding at once cannot get past 50.
-- * Nothing here is shared: the phrases are never visible to anyone else, and
--   sending one is an ordinary message through the ordinary send path (so
--   AutoMod, slowmode, blocks and the rest apply as to any message).

create table if not exists public.quick_replies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  shortcut text not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quick_replies_shortcut_check check (
    char_length(shortcut) between 1 and 32
    and shortcut = lower(btrim(shortcut))
    and shortcut !~ '[[:space:]/]'
  ),
  constraint quick_replies_body_check check (
    char_length(btrim(body)) between 1 and 2000
  ),
  constraint quick_replies_unique_shortcut unique (user_id, shortcut)
);

alter table public.quick_replies enable row level security;

revoke all on public.quick_replies from anon, authenticated;
grant select, insert, update, delete on public.quick_replies to authenticated;

drop policy if exists quick_replies_select_own on public.quick_replies;
create policy quick_replies_select_own
  on public.quick_replies for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists quick_replies_insert_own on public.quick_replies;
create policy quick_replies_insert_own
  on public.quick_replies for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists quick_replies_update_own on public.quick_replies;
create policy quick_replies_update_own
  on public.quick_replies for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists quick_replies_delete_own on public.quick_replies;
create policy quick_replies_delete_own
  on public.quick_replies for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.quick_replies_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.shortcut := lower(btrim(new.shortcut));
  new.body := btrim(new.body);

  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
  end if;

  -- One person's inserts are serialised, so the count below is true.
  perform pg_advisory_xact_lock(
    hashtextextended('quick-replies:' || new.user_id::text, 0)
  );
  if (
    select count(*) from public.quick_replies q where q.user_id = new.user_id
  ) >= 50 then
    raise exception 'You can keep at most 50 quick replies'
      using errcode = '54000';
  end if;
  return new;
end;
$$;

revoke execute on function public.quick_replies_before_write()
  from public, anon, authenticated;

drop trigger if exists quick_replies_before_write on public.quick_replies;
create trigger quick_replies_before_write
  before insert or update on public.quick_replies
  for each row execute function public.quick_replies_before_write();

create index if not exists quick_replies_user_idx
  on public.quick_replies (user_id, created_at);
