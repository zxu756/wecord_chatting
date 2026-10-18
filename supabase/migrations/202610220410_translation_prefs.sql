-- Auto-translate (roadmap A5, part 2 of 2): what each person chose.
--
-- * public.conversation_translation_prefs: per person and conversation,
--   whether "Auto-translate this chat" is on and, optionally, a language for
--   this chat alone (null follows the person's default). Owner-only. A row is
--   only for a conversation the person can read, and goes when they leave it.
-- * public.user_ai_settings: the person's defaults across devices, "Translate
--   to" (null = the language of the app), the languages never translated and
--   a copy of the "AI features" switch (the app keeps the switch on the device
--   and writes it here, so the `ai` function can honour it: null = not copied
--   yet, which counts as on).
--   A table of its own rather than columns of user_notification_settings
--   (202610210300): that table is the push function's input (quiet hours,
--   important contacts) and its triggers validate friends and time zones;
--   AI choices have nothing to do with it, and keeping them apart keeps the
--   push path and its tests untouched. Owner-only.
-- The message translations themselves are in 202610220400.

create table if not exists public.conversation_translation_prefs (
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  auto boolean not null default false,
  target_lang text
    check (target_lang is null or target_lang in ('en', 'zh', 'ja', 'ko', 'es', 'fr')),
  updated_at timestamptz not null default now(),
  primary key (user_id, conversation_id)
);

alter table public.conversation_translation_prefs enable row level security;
revoke all on public.conversation_translation_prefs from anon, authenticated;
grant select, insert, update, delete on public.conversation_translation_prefs to authenticated;

drop policy if exists conversation_translation_prefs_select on public.conversation_translation_prefs;
create policy conversation_translation_prefs_select
  on public.conversation_translation_prefs for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists conversation_translation_prefs_insert on public.conversation_translation_prefs;
create policy conversation_translation_prefs_insert
  on public.conversation_translation_prefs for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists conversation_translation_prefs_update on public.conversation_translation_prefs;
create policy conversation_translation_prefs_update
  on public.conversation_translation_prefs for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and conversation_id in (select public.current_user_readable_conversation_ids())
  );

drop policy if exists conversation_translation_prefs_delete on public.conversation_translation_prefs;
create policy conversation_translation_prefs_delete
  on public.conversation_translation_prefs for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.touch_translation_pref()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists conversation_translation_prefs_touch on public.conversation_translation_prefs;
create trigger conversation_translation_prefs_touch
  before insert or update on public.conversation_translation_prefs
  for each row execute function public.touch_translation_pref();

-- Leaving a conversation (or being removed) takes the choice with it.
create or replace function public.drop_translation_pref_on_leave()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.conversation_translation_prefs p
  where p.user_id = old.user_id and p.conversation_id = old.conversation_id;
  return null;
end;
$$;

revoke execute on function public.drop_translation_pref_on_leave() from public, anon, authenticated;

drop trigger if exists conversation_members_drop_translation_pref on public.conversation_members;
create trigger conversation_members_drop_translation_pref
  after delete on public.conversation_members
  for each row execute function public.drop_translation_pref_on_leave();

create table if not exists public.user_ai_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  translate_target text
    check (translate_target is null or translate_target in ('en', 'zh', 'ja', 'ko', 'es', 'fr')),
  no_translate_langs text[] not null default '{}',
  ai_enabled boolean,
  updated_at timestamptz not null default now(),
  constraint user_ai_settings_langs_check
    check (
      no_translate_langs <@ array['en', 'zh', 'ja', 'ko', 'es', 'fr']
      and cardinality(no_translate_langs) <= 6
    )
);

alter table public.user_ai_settings enable row level security;
revoke all on public.user_ai_settings from anon, authenticated;
grant select, insert, update on public.user_ai_settings to authenticated;

drop policy if exists user_ai_settings_select on public.user_ai_settings;
create policy user_ai_settings_select
  on public.user_ai_settings for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists user_ai_settings_insert on public.user_ai_settings;
create policy user_ai_settings_insert
  on public.user_ai_settings for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists user_ai_settings_update on public.user_ai_settings;
create policy user_ai_settings_update
  on public.user_ai_settings for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Keeps the list tidy: sorted, no repeats.
create or replace function public.user_ai_settings_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.no_translate_langs := coalesce(
    (select array_agg(distinct l order by l) from unnest(new.no_translate_langs) l),
    '{}'
  );
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_ai_settings_tidy on public.user_ai_settings;
create trigger user_ai_settings_tidy
  before insert or update on public.user_ai_settings
  for each row execute function public.user_ai_settings_before_write();
