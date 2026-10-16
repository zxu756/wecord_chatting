-- Message search, part 1: what a message is searched by, and where.
--
-- * The searchable text of a message is its body (custom emoji as their
--   name), a poll's options and a file's name, lower-cased
--   (message_search_document).
-- * Full text: a 'simple' tsvector of that text with every CJK character
--   as its own word (message_search_vector), so a phrase query finds any
--   run of Chinese, Japanese or Korean characters, however short, without
--   a segmenter.
-- * Substrings: pg_trgm on the same text, for the middle of words ("ploy"
--   in "deploy") and as a second way to longer CJK runs.
-- * What a message has (message_search_kinds: image, video, file, voice,
--   poll, sticker, link), for has: filters.
--
-- These live in message_search_entries, one row per searchable message
-- (not recalled, not a system notice), kept in step by a trigger. Search
-- reads that narrow table: index rechecks read stored values instead of
-- recomputing the text of every candidate, and the messages table (and
-- its realtime payloads) stays as it is. Only security definer functions
-- read it. The old body-only tsvector index (202605180010) goes.

create extension if not exists pg_trgm with schema extensions;

-- Spaces around every CJK ideograph, kana, bopomofo and hangul syllable,
-- and half-width katakana.
create or replace function public.search_split_cjk(input text)
returns text
language sql
immutable
parallel safe
as $$
  select regexp_replace(
    coalesce(input, ''),
    '([\x2E80-\x2FDF\x3040-\x30FF\x3100-\x312F\x3190-\x31FF\x3400-\x4DBF\x4E00-\x9FFF\xA960-\xA97F\xAC00-\xD7AF\xF900-\xFAFF\xFF66-\xFF9F])',
    ' \1 ',
    'g'
  );
$$;

create or replace function public.message_search_document(
  message_type text,
  message_body text,
  message_attachment jsonb
)
returns text
language sql
immutable
parallel safe
as $$
  select lower(concat_ws(
    ' ',
    -- <:name:id> and <a:name:id> custom emoji read as :name:.
    regexp_replace(
      coalesce(message_body, ''),
      '<a?:([A-Za-z0-9_]+):[0-9A-Fa-f-]+>',
      ':\1:',
      'g'
    ),
    case
      when message_type = 'poll'
        and jsonb_typeof(message_attachment->'options') = 'array'
      then (
        select string_agg(o->>'text', ' ')
        from jsonb_array_elements(message_attachment->'options') o
      )
    end,
    case
      when message_type = 'file' then message_attachment->>'name'
    end
  ));
$$;

create or replace function public.message_search_vector(
  message_type text,
  message_body text,
  message_attachment jsonb
)
returns tsvector
language sql
immutable
parallel safe
as $$
  select to_tsvector(
    'simple'::regconfig,
    public.search_split_cjk(
      public.message_search_document(
        message_type,
        message_body,
        message_attachment
      )
    )
  );
$$;

create or replace function public.message_search_kinds(
  message_type text,
  message_body text,
  message_attachment jsonb
)
returns text[]
language sql
immutable
parallel safe
as $$
  select array_remove(array[
    case
      when message_type = 'image'
        or (
          message_type = 'file'
          and coalesce(message_attachment->>'mime_type', '') like 'image/%'
        )
      then 'image'
    end,
    case
      when message_type = 'file'
        and (
          message_attachment->>'kind' = 'video'
          or coalesce(message_attachment->>'mime_type', '') like 'video/%'
        )
      then 'video'
    end,
    case when message_type = 'file' then 'file' end,
    case when message_type = 'voice' then 'voice' end,
    case when message_type = 'poll' then 'poll' end,
    case when message_type = 'sticker' then 'sticker' end,
    case
      when coalesce(message_body, '') ~* '(https?://|www\.)[^[:space:]]'
      then 'link'
    end
  ], null);
$$;

-- A LIKE pattern matching [term] anywhere, lower-cased.
create or replace function public.search_like_pattern(term text)
returns text
language sql
immutable
parallel safe
as $$
  select '%' || replace(replace(replace(
    lower(coalesce(term, '')),
    '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

create table if not exists public.message_search_entries (
  message_id uuid primary key
    references public.messages(id) on delete cascade,
  conversation_id uuid not null,
  sender_id uuid not null,
  created_at timestamptz not null,
  document text not null,
  vector tsvector not null,
  kinds text[] not null default '{}'
);

alter table public.message_search_entries enable row level security;
revoke all on public.message_search_entries from anon, authenticated;

-- Keeps a message's entry in step: written for searchable messages,
-- removed when they are recalled.
create or replace function public.sync_message_search_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.recalled_at is not null or new.type = 'system' then
    if tg_op = 'UPDATE' then
      delete from public.message_search_entries where message_id = new.id;
    end if;
    return null;
  end if;
  if tg_op = 'UPDATE'
    and new.body is not distinct from old.body
    and new.attachment is not distinct from old.attachment
    and new.type is not distinct from old.type
    and old.recalled_at is null
  then
    return null;
  end if;
  insert into public.message_search_entries as e (
    message_id, conversation_id, sender_id, created_at, document, vector, kinds
  )
  values (
    new.id,
    new.conversation_id,
    new.sender_id,
    new.created_at,
    public.message_search_document(new.type, new.body, new.attachment),
    public.message_search_vector(new.type, new.body, new.attachment),
    public.message_search_kinds(new.type, new.body, new.attachment)
  )
  on conflict (message_id) do update
  set document = excluded.document,
    vector = excluded.vector,
    kinds = excluded.kinds;
  return null;
end;
$$;

revoke execute on function public.sync_message_search_entry() from public;
revoke execute on function public.sync_message_search_entry() from anon;
revoke execute on function public.sync_message_search_entry() from authenticated;

drop trigger if exists messages_sync_search_entry on public.messages;
create trigger messages_sync_search_entry
  after insert or update of type, body, attachment, recalled_at
  on public.messages
  for each row execute function public.sync_message_search_entry();

insert into public.message_search_entries (
  message_id, conversation_id, sender_id, created_at, document, vector, kinds
)
select
  m.id,
  m.conversation_id,
  m.sender_id,
  m.created_at,
  public.message_search_document(m.type, m.body, m.attachment),
  public.message_search_vector(m.type, m.body, m.attachment),
  public.message_search_kinds(m.type, m.body, m.attachment)
from public.messages m
where m.recalled_at is null
  and m.type <> 'system'
on conflict (message_id) do nothing;

-- Scopes and dates; from:; newest first across everything.
create index if not exists message_search_entries_conversation_idx
  on public.message_search_entries (conversation_id, created_at desc, message_id desc);
create index if not exists message_search_entries_sender_idx
  on public.message_search_entries (sender_id, created_at desc);
create index if not exists message_search_entries_created_idx
  on public.message_search_entries (created_at desc, message_id desc);
-- Words, substrings and has:.
create index if not exists message_search_entries_vector_idx
  on public.message_search_entries using gin (vector);
create index if not exists message_search_entries_trgm_idx
  on public.message_search_entries
  using gin (document extensions.gin_trgm_ops);
create index if not exists message_search_entries_kinds_idx
  on public.message_search_entries using gin (kinds);

-- mentions: walks a person's mentions by message.
create index if not exists message_mentions_user_kind_message_idx
  on public.message_mentions (user_id, message_id)
  where kind = 'user';

drop index if exists public.messages_body_search_idx;

grant execute on function public.search_split_cjk(text) to authenticated;
grant execute on function public.message_search_document(text, text, jsonb) to authenticated;
grant execute on function public.message_search_vector(text, text, jsonb) to authenticated;
grant execute on function public.message_search_kinds(text, text, jsonb) to authenticated;
grant execute on function public.search_like_pattern(text) to authenticated;
