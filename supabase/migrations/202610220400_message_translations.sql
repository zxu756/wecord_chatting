-- Auto-translate (roadmap A5, part 1 of 2): a cache of message translations.
--
-- The `ai` function's translate_batch action translates the messages a person
-- is looking at. Each translation is kept here, once per (message, language),
-- so the next reader who needs the same translation costs no model call.
--
-- * public.message_translations: message_id, target_lang, text, model,
--   created_at; primary key (message_id, target_lang). source_lang is the
--   language the model recognised in the original ('other' when it is none of
--   the six); it lets "don't translate these languages" work for cache hits
--   too. When the original is already in target_lang, text is the original
--   itself (so the answer is cached and nobody asks again).
-- * Who reads it: the policy asks the messages table itself, as the caller
--   (exactly as message_edits does, 202610220210), so only people who can
--   select the message can select its translations: membership, the
--   disappearing-messages expiry and a message waiting for the AI guard
--   (202610170091) all apply. message_visible_to_current_user takes the
--   message's columns, not its id, and would only repeat that policy.
-- * Who writes it: nobody signed in. Clients get select only; the `ai`
--   function writes with the service role, after reading the message as the
--   caller.
-- * The translations go with the message, through a trigger so that no
--   function that changes a message has to be redefined:
--     - text changed (edit_message, moderation, anything else): cleared;
--     - recalled_at set (recall, moderator delete, the AI guard's remove,
--       the copies of a recalled published message): cleared;
--     - review_state set (the guard holds, checks or removes it): cleared;
--     - expires_at reached: reads skip an expired message at once (the
--       policy), and purge_expired_messages deletes the message, which
--       deletes the rows through the foreign key. An expiry that is moved
--       into the past clears them too;
--     - deleting a conversation or an account deletes the messages and the
--       rows follow.

create table if not exists public.message_translations (
  message_id uuid not null references public.messages(id) on delete cascade,
  target_lang text not null
    check (target_lang in ('en', 'zh', 'ja', 'ko', 'es', 'fr')),
  text text not null,
  source_lang text
    check (source_lang is null or source_lang in ('en', 'zh', 'ja', 'ko', 'es', 'fr', 'other')),
  model text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, target_lang)
);

alter table public.message_translations enable row level security;
revoke all on public.message_translations from anon, authenticated;
grant select on public.message_translations to authenticated;
grant select, insert, update, delete on public.message_translations to service_role;

drop policy if exists message_translations_select on public.message_translations;
create policy message_translations_select
  on public.message_translations for select
  to authenticated
  using (
    exists (
      select 1 from public.messages m where m.id = message_translations.message_id
    )
  );

create or replace function public.clear_message_translations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recalled_at is not null
    or new.body is distinct from old.body
    or new.review_state is not null
    or (new.expires_at is not null and new.expires_at <= now())
  then
    delete from public.message_translations t where t.message_id = old.id;
  end if;
  return null;
end;
$$;

revoke execute on function public.clear_message_translations() from public, anon, authenticated;

drop trigger if exists messages_clear_translations on public.messages;
create trigger messages_clear_translations
  after update of body, recalled_at, review_state, expires_at on public.messages
  for each row execute function public.clear_message_translations();

-- How the `ai` function stores translations: only for the text it translated,
-- and only for a message that is still there for readers. A message edited,
-- recalled, held or expired while the model was working would otherwise get a
-- stale translation after its cleanup already ran. The message row is locked
-- (for share) while the row is written, so an edit that comes in after waits
-- and then clears what was just stored. The service role only.
--
-- p_rows: [{message_id, target_lang, text, source_lang, model, source_text}]
-- where source_text is the original text that was translated.
create or replace function public.store_message_translations(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  stored integer;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    return 0;
  end if;

  with wanted as (
    select r.*
    from jsonb_to_recordset(p_rows) as r(
      message_id uuid,
      target_lang text,
      text text,
      source_lang text,
      model text,
      source_text text
    )
    where r.target_lang in ('en', 'zh', 'ja', 'ko', 'es', 'fr')
      and r.text is not null
      and r.model is not null
  ),
  current as (
    select w.*
    from wanted w
    join public.messages m on m.id = w.message_id
    where m.body is not distinct from w.source_text
      and m.type = 'text'
      and m.recalled_at is null
      and m.review_state is null
      and (m.expires_at is null or m.expires_at > now())
    for share of m
  ),
  written as (
    insert into public.message_translations as t (
      message_id, target_lang, text, source_lang, model
    )
    select
      c.message_id,
      c.target_lang,
      c.text,
      case
        when c.source_lang in ('en', 'zh', 'ja', 'ko', 'es', 'fr', 'other') then c.source_lang
      end,
      c.model
    from current c
    on conflict (message_id, target_lang) do update
    set text = excluded.text,
        source_lang = excluded.source_lang,
        model = excluded.model,
        created_at = now()
    returning 1
  )
  select count(*) into stored from written;
  return stored;
end;
$$;

revoke execute on function public.store_message_translations(jsonb) from public, anon, authenticated;
grant execute on function public.store_message_translations(jsonb) to service_role;
