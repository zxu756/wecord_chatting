-- Official notices (K6), part 1 of 3: the tables and what a person can do
-- with them. Part 2 (202610240630) holds the admin functions and the push;
-- feedback replies (202610240650, K7) are notices for one person.
--
-- * announcements: what "WeCord team" says. kind 'announcement' goes to
--   everybody; kind 'feedback_reply' (K7) goes to one person
--   (audience_user_id) and says nothing to anybody else. Every notice has an
--   English and a Chinese text (at least one title); the app shows the one in
--   its language and the other when that one is empty. "WeCord team" is only
--   the name on the card, not an account: nothing here creates a user or
--   names one.
-- * announcement_states: per person, whether they have read a notice and
--   whether they dismissed it.
-- * A notice is retracted by setting retracted_at: it vanishes from every
--   inbox at once. Notices are never sent as chat messages.
--
-- Nobody reads or writes the tables through the API. A person lists their own
-- notices with list_my_announcements, and reads or dismisses them with the
-- two functions below.

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'announcement'
    check (kind in ('announcement', 'feedback_reply')),
  title_en text not null default '',
  title_zh text not null default '',
  body_en text not null default '',
  body_zh text not null default '',
  -- Who it is for; null is everybody.
  audience_user_id uuid references public.profiles(id) on delete cascade,
  -- The feedback a reply answers (the foreign key comes with the feedback
  -- table, 202610240640).
  feedback_id uuid,
  -- Whether one push goes out for it, and how far that has got.
  push boolean not null default false,
  push_cursor uuid,
  push_done_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  published_at timestamptz not null default now(),
  retracted_at timestamptz,
  retracted_by uuid references public.profiles(id) on delete set null,
  constraint announcements_text_lengths check (
    char_length(title_en) <= 120 and char_length(title_zh) <= 120
    and char_length(body_en) <= 2000 and char_length(body_zh) <= 2000
  ),
  constraint announcements_has_title check (
    btrim(title_en) <> '' or btrim(title_zh) <> ''
  ),
  constraint announcements_audience_matches_kind check (
    (kind = 'feedback_reply') = (audience_user_id is not null)
  ),
  constraint announcements_push_only_for_everybody check (
    not push or kind = 'announcement'
  )
);

create index if not exists announcements_published_idx
  on public.announcements (published_at desc)
  where retracted_at is null;
create index if not exists announcements_audience_idx
  on public.announcements (audience_user_id, published_at desc)
  where audience_user_id is not null;
create index if not exists announcements_feedback_idx
  on public.announcements (feedback_id)
  where feedback_id is not null;

create table if not exists public.announcement_states (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  read_at timestamptz,
  dismissed_at timestamptz,
  primary key (announcement_id, user_id)
);

create index if not exists announcement_states_user_idx
  on public.announcement_states (user_id);

alter table public.announcements enable row level security;
alter table public.announcement_states enable row level security;
revoke all on public.announcements from public, anon, authenticated;
revoke all on public.announcement_states from public, anon, authenticated;

-- Whether [uid] may see [a]: not retracted, and either meant for them or for
-- everybody and published after they joined, within the last 30 days (a reply
-- stays 90 days). Internal.
create or replace function public.announcement_visible_to(
  a public.announcements,
  uid uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select uid is not null
    and a.retracted_at is null
    and case
      when a.audience_user_id is not null then
        a.audience_user_id = uid and a.published_at > now() - interval '90 days'
      else
        a.published_at > now() - interval '30 days'
        and a.published_at >= coalesce(
          (select p.created_at from public.profiles p where p.id = uid),
          'infinity'::timestamptz
        )
    end;
$$;

revoke execute on function public.announcement_visible_to(public.announcements, uuid)
  from public, anon, authenticated;

-- The caller's notices, newest first (30 at most), without the ones they
-- dismissed.
create or replace function public.list_my_announcements()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  result jsonb;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(e.entry order by e.published_at desc), '[]'::jsonb)
  into result
  from (
    select
      jsonb_build_object(
        'id', a.id,
        'kind', a.kind,
        'title_en', a.title_en,
        'title_zh', a.title_zh,
        'body_en', a.body_en,
        'body_zh', a.body_zh,
        'published_at', a.published_at,
        'read', s.read_at is not null
      ) as entry,
      a.published_at
    from public.announcements a
    left join public.announcement_states s
      on s.announcement_id = a.id and s.user_id = uid
    where public.announcement_visible_to(a, uid)
      and s.dismissed_at is null
    order by a.published_at desc
    limit 30
  ) e;

  return result;
end;
$$;

-- Marks a notice read. Does nothing for a notice the caller cannot see.
create or replace function public.mark_announcement_read(target_announcement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  insert into public.announcement_states (announcement_id, user_id, read_at)
  select a.id, uid, now()
  from public.announcements a
  where a.id = target_announcement_id
    and public.announcement_visible_to(a, uid)
  on conflict (announcement_id, user_id) do update
  set read_at = coalesce(public.announcement_states.read_at, excluded.read_at);
end;
$$;

-- Takes a notice off the caller's list (and marks it read).
create or replace function public.dismiss_announcement(target_announcement_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  insert into public.announcement_states (announcement_id, user_id, read_at, dismissed_at)
  select a.id, uid, now(), now()
  from public.announcements a
  where a.id = target_announcement_id
    and public.announcement_visible_to(a, uid)
  on conflict (announcement_id, user_id) do update
  set read_at = coalesce(public.announcement_states.read_at, excluded.read_at),
      dismissed_at = coalesce(
        public.announcement_states.dismissed_at,
        excluded.dismissed_at
      );
end;
$$;

revoke execute on function public.list_my_announcements() from public, anon;
revoke execute on function public.mark_announcement_read(uuid) from public, anon;
revoke execute on function public.dismiss_announcement(uuid) from public, anon;
grant execute on function public.list_my_announcements() to authenticated;
grant execute on function public.mark_announcement_read(uuid) to authenticated;
grant execute on function public.dismiss_announcement(uuid) to authenticated;
