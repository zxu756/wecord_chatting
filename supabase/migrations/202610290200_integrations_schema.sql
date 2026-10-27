-- Rich webhooks, RSS feeds and GitHub (roadmap I6), part 1 of 4: the schema,
-- and what a card may hold.
--
-- Incoming webhooks (202610130024) post text as their channel. Three things
-- are added on top of them, and all three post through the same
-- circle_webhooks row, so everything that already treats a webhook message
-- as one (no edit, unread for everyone, no slowmode, AutoMod and AI guard
-- leaving it alone, search, push, K1) keeps doing so without a change:
--
-- * Cards. messages.embeds is a jsonb object {cards, components?, summary?}:
--     cards       1 to 3 cards, each {title?, url?, description?, color?,
--                 author?{name, url?, icon_url?}, fields?[{name, value,
--                 inline?}], image?{url}, thumbnail?{url}, footer?{text,
--                 icon_url?}, timestamp?}
--     components  rows of LINK buttons only (a webhook has nobody to answer a
--                 press), cleaned by normalize_message_components (I1)
--     summary     true when the message body is only a one-line summary of
--                 the first card (so a notification, the chat list and
--                 search have a text); the app then draws just the cards.
--   Only the server sets it, only on a webhook's text message, and only
--   through normalize_message_embeds, which reuses I1's text and link rules
--   (components_clean_text, components_https_url_ok, components_id_ok):
--   unknown keys are dropped, texts are plain text with no control, hidden or
--   direction-changing characters, every address is https only, the whole is
--   at most 8 KB. The app draws every text as plain text.
-- * Feeds (channel_feeds): an RSS or Atom address a channel follows. The
--   Edge Function feed-fetch reads it every 15 minutes and posts new items.
-- * GitHub (channel_github_hooks): a repository's own webhook, signed with a
--   secret made here and shown once, that posts push / pull request / issue /
--   release / comment / workflow events as cards.
--
-- A feed or a GitHub hook owns one hidden circle_webhooks row (kind 'rss' or
-- 'github', a token nobody knows): that row gives the messages their
-- webhook_id, name and the person they are posted as (its created_by). The
-- management functions of plain webhooks only see kind 'incoming' (part 2).
--
-- Both tables are closed to clients (RLS on, no policy, no grant); people
-- manage them through the functions of part 2.

-- ------------------------------------------------------------ the columns

alter table public.circle_webhooks
  add column if not exists kind text not null default 'incoming';

alter table public.circle_webhooks
  drop constraint if exists circle_webhooks_kind;
alter table public.circle_webhooks
  add constraint circle_webhooks_kind check (kind in ('incoming', 'rss', 'github'));

alter table public.messages
  add column if not exists embeds jsonb;

alter table public.messages
  drop constraint if exists messages_embeds_object;
alter table public.messages
  add constraint messages_embeds_object check (
    embeds is null or (
      jsonb_typeof(embeds) = 'object'
      and jsonb_typeof(embeds->'cards') = 'array'
      and jsonb_array_length(embeds->'cards') between 1 and 3
      and octet_length(embeds::text) <= 12288
    )
  );

-- ------------------------------------------------------------- checking

-- A paragraph of plain text: trimmed, [min_length] to [max_length]
-- characters, new lines allowed (at most one empty line in a row), no other
-- control character, nothing that reorders or hides text.
create or replace function public.embeds_clean_block(
  raw jsonb,
  field_name text,
  min_length integer,
  max_length integer
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text;
begin
  if raw is null or jsonb_typeof(raw) = 'null' then
    cleaned := '';
  elsif jsonb_typeof(raw) <> 'string' then
    raise exception '% must be a string', field_name using errcode = '22023';
  else
    cleaned := btrim(replace(replace(raw #>> '{}', E'\r\n', E'\n'), E'\r', E'\n'));
  end if;

  if cleaned ~ '[\u0001-\u0009\u000b-\u001f\u007f​-‏‪-‮⁠-⁤⁦-⁩﻿]' then
    raise exception '% has characters that are not allowed', field_name
      using errcode = '22023';
  end if;

  cleaned := regexp_replace(cleaned, E'\n{3,}', E'\n\n', 'g');

  if char_length(cleaned) < min_length or char_length(cleaned) > max_length then
    raise exception '% must be % to % characters', field_name, min_length, max_length
      using errcode = '22023';
  end if;
  return cleaned;
end;
$$;

-- Makes any text fit for a card instead of refusing it: the characters a card
-- may not have are dropped, spaces and lines are tidied, and what is too long
-- is cut with an ellipsis. For text that comes from other people's servers
-- (a feed, GitHub), where one odd character must not lose the whole item.
create or replace function public.embeds_strip_text(
  raw text,
  max_length integer,
  keep_lines boolean default false
)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  cleaned text := coalesce(raw, '');
begin
  cleaned := replace(replace(cleaned, E'\r\n', E'\n'), E'\r', E'\n');
  cleaned := regexp_replace(
    cleaned,
    '[\u0000-\u0008\u000b-\u001f\u007f​-‏‪-‮⁠-⁤⁦-⁩﻿]',
    '',
    'g'
  );
  if keep_lines then
    cleaned := regexp_replace(cleaned, '[ \t]+', ' ', 'g');
    cleaned := regexp_replace(cleaned, E' ?\n ?', E'\n', 'g');
    cleaned := regexp_replace(cleaned, E'\n{3,}', E'\n\n', 'g');
  else
    cleaned := regexp_replace(cleaned, '\s+', ' ', 'g');
  end if;
  cleaned := btrim(cleaned);
  if char_length(cleaned) > max_length then
    cleaned := btrim(left(cleaned, greatest(max_length - 1, 0))) || '…';
  end if;
  return cleaned;
end;
$$;

-- An address on a card: https only (components_https_url_ok).
create or replace function public.embeds_url(raw jsonb, field_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
begin
  if jsonb_typeof(raw) is distinct from 'string'
    or not public.components_https_url_ok(raw #>> '{}')
  then
    raise exception '% needs an https address of a website (no addresses, no other ports, up to 500 characters)', field_name
      using errcode = '22023';
  end if;
  return raw #>> '{}';
end;
$$;

-- The stripe colour of a card: "#rrggbb" or a number from 0 to 16777215.
create or replace function public.embeds_color(raw jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  value numeric;
begin
  if jsonb_typeof(raw) = 'string' and (raw #>> '{}') ~ '^#[0-9a-fA-F]{6}$' then
    return lower(raw #>> '{}');
  end if;
  if jsonb_typeof(raw) = 'number' then
    value := (raw #>> '{}')::numeric;
    if value = trunc(value) and value between 0 and 16777215 then
      return '#' || lpad(to_hex(value::integer), 6, '0');
    end if;
  end if;
  raise exception 'color is #rrggbb or a number from 0 to 16777215'
    using errcode = '22023';
end;
$$;

-- One card, cleaned (the texts of all a message's cards are at most 6000
-- characters together, checked by normalize_message_embeds).
create or replace function public.normalize_embed_card(raw jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  card jsonb := '{}'::jsonb;
  part jsonb;
  field jsonb;
  fields_out jsonb;
  piece text;
begin
  if jsonb_typeof(raw) <> 'object' then
    raise exception 'A card must be an object' using errcode = '22023';
  end if;

  if raw ? 'title' and jsonb_typeof(raw->'title') <> 'null' then
    card := card || jsonb_build_object(
      'title', public.components_clean_text(raw->'title', 'A card title', 1, 120)
    );
  end if;
  if raw ? 'url' and jsonb_typeof(raw->'url') <> 'null' then
    card := card || jsonb_build_object('url', public.embeds_url(raw->'url', 'A card url'));
  end if;
  if raw ? 'description' and jsonb_typeof(raw->'description') <> 'null' then
    piece := public.embeds_clean_block(raw->'description', 'A card description', 0, 1500);
    if piece <> '' then
      card := card || jsonb_build_object('description', piece);
    end if;
  end if;
  if raw ? 'color' and jsonb_typeof(raw->'color') <> 'null' then
    card := card || jsonb_build_object('color', public.embeds_color(raw->'color'));
  end if;

  if raw ? 'author' and jsonb_typeof(raw->'author') <> 'null' then
    part := raw->'author';
    if jsonb_typeof(part) <> 'object' then
      raise exception 'A card author must be an object' using errcode = '22023';
    end if;
    card := card || jsonb_build_object('author', jsonb_strip_nulls(jsonb_build_object(
      'name', public.components_clean_text(part->'name', 'An author name', 1, 60),
      'url', case when part ? 'url' and jsonb_typeof(part->'url') <> 'null'
        then public.embeds_url(part->'url', 'An author url') end,
      'icon_url', case when part ? 'icon_url' and jsonb_typeof(part->'icon_url') <> 'null'
        then public.embeds_url(part->'icon_url', 'An author icon_url') end
    )));
  end if;

  if raw ? 'fields' and jsonb_typeof(raw->'fields') <> 'null' then
    if jsonb_typeof(raw->'fields') <> 'array' or jsonb_array_length(raw->'fields') > 10 then
      raise exception 'A card has at most 10 fields' using errcode = '22023';
    end if;
    fields_out := '[]'::jsonb;
    for field in select value from jsonb_array_elements(raw->'fields') loop
      if jsonb_typeof(field) <> 'object' then
        raise exception 'A field must be an object' using errcode = '22023';
      end if;
      if field ? 'inline' and jsonb_typeof(field->'inline') not in ('boolean', 'null') then
        raise exception 'inline must be true or false' using errcode = '22023';
      end if;
      fields_out := fields_out || jsonb_build_array(jsonb_build_object(
        'name', public.components_clean_text(field->'name', 'A field name', 1, 60),
        'value', public.embeds_clean_block(field->'value', 'A field value', 1, 300),
        'inline', coalesce((field->>'inline')::boolean, false)
      ));
    end loop;
    if jsonb_array_length(fields_out) > 0 then
      card := card || jsonb_build_object('fields', fields_out);
    end if;
  end if;

  foreach piece in array array['image', 'thumbnail'] loop
    if raw ? piece and jsonb_typeof(raw->piece) <> 'null' then
      part := raw->piece;
      -- {"url": "https://..."} like Discord, or the address itself.
      if jsonb_typeof(part) = 'object' then
        part := part->'url';
      end if;
      card := card || jsonb_build_object(
        piece,
        jsonb_build_object('url', public.embeds_url(part, 'A card ' || piece))
      );
    end if;
  end loop;

  if raw ? 'footer' and jsonb_typeof(raw->'footer') <> 'null' then
    part := raw->'footer';
    if jsonb_typeof(part) <> 'object' then
      raise exception 'A card footer must be an object' using errcode = '22023';
    end if;
    card := card || jsonb_build_object('footer', jsonb_strip_nulls(jsonb_build_object(
      'text', public.components_clean_text(part->'text', 'A footer text', 1, 100),
      'icon_url', case when part ? 'icon_url' and jsonb_typeof(part->'icon_url') <> 'null'
        then public.embeds_url(part->'icon_url', 'A footer icon_url') end
    )));
  end if;

  if raw ? 'timestamp' and jsonb_typeof(raw->'timestamp') <> 'null' then
    if jsonb_typeof(raw->'timestamp') <> 'string'
      or (raw->>'timestamp') !~ '^\d{4}-\d{2}-\d{2}([T ][0-9:.]+)?(Z|[+-]\d{2}:?\d{2})?$'
    then
      raise exception 'timestamp is an ISO 8601 time' using errcode = '22023';
    end if;
    begin
      card := card || jsonb_build_object(
        'timestamp',
        to_char((raw->>'timestamp')::timestamptz at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      );
    exception when others then
      raise exception 'timestamp is an ISO 8601 time' using errcode = '22023';
    end;
  end if;

  -- Something to show.
  if not (
    card ? 'title' or card ? 'description' or card ? 'fields' or card ? 'image'
    or card ? 'thumbnail' or card ? 'author'
  ) then
    raise exception 'A card needs a title, a description, fields, an author or a picture'
      using errcode = '22023';
  end if;
  return card;
end;
$$;

-- What a webhook may attach to a message, cleaned: raises 22023 saying what is
-- wrong, returns null for nothing. [raw_embeds] is a list of cards,
-- [raw_components] rows of link buttons.
create or replace function public.normalize_message_embeds(
  raw_embeds jsonb,
  raw_components jsonb default null
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  card jsonb;
  cards_out jsonb := '[]'::jsonb;
  components_out jsonb;
  result jsonb;
begin
  if raw_embeds is not null and jsonb_typeof(raw_embeds) <> 'null' then
    if jsonb_typeof(raw_embeds) <> 'array' then
      raise exception 'embeds must be a list of cards' using errcode = '22023';
    end if;
    if jsonb_array_length(raw_embeds) > 3 then
      raise exception 'At most 3 cards in a message' using errcode = '22023';
    end if;
    for card in select value from jsonb_array_elements(raw_embeds) loop
      cards_out := cards_out || jsonb_build_array(public.normalize_embed_card(card));
    end loop;
  end if;

  components_out := public.normalize_message_components(raw_components);
  if components_out is not null and exists (
    select 1
    from jsonb_array_elements(components_out) r, jsonb_array_elements(r.value) c
    where c.value->>'type' <> 'link'
  ) then
    raise exception 'A webhook can only add link buttons (nobody answers a press)'
      using errcode = '22023';
  end if;

  if jsonb_array_length(cards_out) = 0 then
    if components_out is not null then
      raise exception 'Link buttons need at least one card' using errcode = '22023';
    end if;
    return null;
  end if;

  result := jsonb_build_object('cards', cards_out);
  if components_out is not null then
    result := result || jsonb_build_object('components', components_out);
  end if;

  if char_length(public.message_embeds_text(result)) > 6000 then
    raise exception 'The cards are too long (6000 characters in all)'
      using errcode = '22023';
  end if;
  if octet_length(result::text) > 8192 then
    raise exception 'The cards are too big (8 KB at most)' using errcode = '22023';
  end if;
  return result;
end;
$$;

-- Every text a person reads on a message's cards, in one string, so AutoMod
-- can look at it and a one-line summary can be made.
create or replace function public.message_embeds_text(embeds jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(t, E'\n'), '')
  from (
    select c.value->>'title' as t
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c
    union all
    select c.value->>'description'
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c
    union all
    select c.value#>>'{author,name}'
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c
    union all
    select f.value->>'name'
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c,
      jsonb_array_elements(coalesce(c.value->'fields', '[]'::jsonb)) f
    union all
    select f.value->>'value'
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c,
      jsonb_array_elements(coalesce(c.value->'fields', '[]'::jsonb)) f
    union all
    select c.value#>>'{footer,text}'
    from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) c
    union all
    select public.message_components_text(embeds->'components')
  ) texts
  where t is not null and t <> '';
$$;

-- One line for a message that is only cards: the first card's title, else the
-- first line of its description, else its first field, else its author.
create or replace function public.message_embeds_summary(embeds jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select public.embeds_strip_text(
    coalesce(
      nullif(c.value->>'title', ''),
      nullif(split_part(c.value->>'description', E'\n', 1), ''),
      nullif(concat_ws(': ', c.value#>>'{fields,0,name}', c.value#>>'{fields,0,value}'), ''),
      nullif(c.value#>>'{author,name}', ''),
      'Card'
    ),
    200
  )
  from jsonb_array_elements(coalesce(embeds->'cards', '[]'::jsonb)) with ordinality c(value, position)
  where c.position = 1;
$$;

revoke execute on function public.embeds_clean_block(jsonb, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.embeds_strip_text(text, integer, boolean) from public, anon, authenticated;
revoke execute on function public.embeds_url(jsonb, text) from public, anon, authenticated;
revoke execute on function public.embeds_color(jsonb) from public, anon, authenticated;
revoke execute on function public.normalize_embed_card(jsonb) from public, anon, authenticated;
revoke execute on function public.normalize_message_embeds(jsonb, jsonb) from public, anon, authenticated;
revoke execute on function public.message_embeds_text(jsonb) from public, anon, authenticated;
revoke execute on function public.message_embeds_summary(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------ the guard

-- Cards are the server's: a signed-in person's own insert or update never
-- sets them (current_user is then authenticated or anon), and only a webhook's
-- plain text message can have them, so nobody can dress a person's message,
-- a poll or a system line up as one. They are cleaned again here. Deleting a
-- message drops its cards.
create or replace function public.messages_guard_embeds()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.embeds is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.embeds is not distinct from old.embeds then
    if new.recalled_at is not null then
      new.embeds := null;
    end if;
    return new;
  end if;

  if current_user in ('authenticated', 'anon') then
    raise exception 'Cards are set by the server' using errcode = '42501';
  end if;

  if new.recalled_at is not null then
    new.embeds := null;
    return new;
  end if;

  if new.type <> 'text'
    or new.webhook_id is null
    or new.webhook_name is null
    or new.forwarded_from is not null
    or new.crosspost is not null
  then
    raise exception 'Only a webhook''s own text message can have cards'
      using errcode = '42501';
  end if;

  new.embeds := public.normalize_message_embeds(
    new.embeds->'cards',
    new.embeds->'components'
  ) || case
    when coalesce((new.embeds->>'summary')::boolean, false)
      then '{"summary": true}'::jsonb
    else '{}'::jsonb
  end;
  return new;
end;
$$;

revoke execute on function public.messages_guard_embeds() from public, anon, authenticated;

drop trigger if exists messages_guard_embeds on public.messages;
create trigger messages_guard_embeds
  before insert or update on public.messages
  for each row
  when (new.embeds is not null)
  execute function public.messages_guard_embeds();

-- ------------------------------------------------------------ the tables

-- A feed a channel follows.
create table if not exists public.channel_feeds (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  channel_id uuid not null,
  webhook_id uuid not null unique references public.circle_webhooks(id) on delete cascade,
  url text not null,
  -- The feed's own title, filled in by the first good read (at most 80).
  title text,
  enabled boolean not null default true,
  -- failing | creator_lost_access | creator_gone
  paused_reason text,
  consecutive_failures integer not null default 0,
  last_status integer,
  last_error text,
  last_fetched_at timestamptz,
  last_success_at timestamptz,
  last_item_at timestamptz,
  next_fetch_at timestamptz not null default now(),
  -- A claimed feed is left alone until then (a crashed read comes back).
  lease_until timestamptz,
  etag text,
  last_modified text,
  -- Short hashes of the items already seen, newest first, at most 200.
  seen_keys text[] not null default '{}',
  -- False until the first good read: that read posts nothing, it only
  -- remembers what is there.
  initialized boolean not null default false,
  items_posted integer not null default 0,
  window_day date not null default current_date,
  window_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint channel_feeds_url_length check (char_length(url) between 12 and 500),
  constraint channel_feeds_title_length check (title is null or char_length(title) between 1 and 80),
  constraint channel_feeds_paused_reason check (
    paused_reason is null
    or paused_reason in ('failing', 'creator_lost_access', 'creator_gone')
  ),
  constraint channel_feeds_seen_size check (cardinality(seen_keys) <= 200),
  constraint channel_feeds_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create unique index if not exists channel_feeds_channel_url_idx
  on public.channel_feeds (channel_id, url);
create index if not exists channel_feeds_circle_idx
  on public.channel_feeds (circle_id);
create index if not exists channel_feeds_due_idx
  on public.channel_feeds (next_fetch_at)
  where enabled;

alter table public.channel_feeds enable row level security;
revoke all on public.channel_feeds from public, anon, authenticated;

-- A repository's webhook that posts into a channel.
create table if not exists public.channel_github_hooks (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  channel_id uuid not null,
  webhook_id uuid not null unique references public.circle_webhooks(id) on delete cascade,
  -- What the channel calls it (the repository, usually).
  label text not null,
  -- push, pull_request, issues, issue_comment, release, workflow_run
  events text[] not null,
  -- Signs what GitHub sends (X-Hub-Signature-256). Shown once when made;
  -- only the github Edge Function (service role) can read it back.
  secret text not null,
  enabled boolean not null default true,
  -- creator_lost_access | creator_gone
  paused_reason text,
  last_delivery_at timestamptz,
  last_event text,
  deliveries_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint channel_github_hooks_label_length check (
    label = btrim(label) and char_length(label) between 1 and 80
  ),
  constraint channel_github_hooks_events check (
    cardinality(events) between 1 and 6
    and events <@ array['push', 'pull_request', 'issues', 'issue_comment', 'release', 'workflow_run']
  ),
  constraint channel_github_hooks_secret_format check (secret ~ '^[A-Za-z0-9_-]{43}$'),
  constraint channel_github_hooks_paused_reason check (
    paused_reason is null or paused_reason in ('creator_lost_access', 'creator_gone')
  ),
  constraint channel_github_hooks_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists channel_github_hooks_channel_idx
  on public.channel_github_hooks (channel_id, created_at);
create index if not exists channel_github_hooks_circle_idx
  on public.channel_github_hooks (circle_id);

alter table public.channel_github_hooks enable row level security;
revoke all on public.channel_github_hooks from public, anon, authenticated;

-- GitHub deliveries seen in the last minutes, so one request sent twice
-- (a retry, a replay of a captured request) posts once.
create table if not exists public.github_deliveries (
  hook_id uuid not null references public.channel_github_hooks(id) on delete cascade,
  delivery_id text not null,
  received_at timestamptz not null default now(),
  primary key (hook_id, delivery_id),
  constraint github_deliveries_id_length check (char_length(delivery_id) between 1 and 80)
);

create index if not exists github_deliveries_received_idx
  on public.github_deliveries (received_at);

alter table public.github_deliveries enable row level security;
revoke all on public.github_deliveries from public, anon, authenticated;
