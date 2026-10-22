-- Interactive components and interaction callbacks (roadmap I1), part 1 of 6:
-- the schema, and what a message may carry.
--
-- A bot (circle_bots, 202610160030) can put buttons, link buttons and drop-down
-- lists on its messages (messages.components). Members press them; the press is
-- a row in bot_interactions (the table slash commands already use) that the bot
-- gets by polling or on a signed callback (parts 4 and 5).
--
-- * messages.components: a jsonb array of rows, each row an array of 1 to 5
--   components, at most 5 rows. Only bots can set it, only through the
--   bot_api_* functions (the clients' roles are refused by a trigger), and
--   whatever is stored went through normalize_message_components: unknown
--   keys are dropped, texts are cleaned (no control or direction-changing
--   characters), ids are unique, link buttons are https only, the whole thing is
--   at most 8 KB. The app draws every text as plain text.
--     button  {type, id, label, style: primary|secondary|danger, disabled?,
--              modal?: {title, fields: [{id, label, style: short|paragraph,
--              required, placeholder?, max_length}]}}
--     link    {type, label, url}
--     select  {type, id, placeholder?, options: [{label, value,
--              description?, default?}], min_values, max_values, disabled?}
-- * bot_interactions grows from "slash command" to "slash command or a press on
--   a component": kind, the message pressed on (or the private reply of a bot,
--   bot_ephemeral_messages), which component, what was chosen or typed, and the
--   state of the callback delivery (part 5). Rows of commands are unchanged.
-- * bot_ephemeral_messages: a bot's reply that only the person who pressed
--   sees. It is a table of its own, not a message: it is never in the chat's
--   history, unread counts, search, pushes, exports of other people or the AI
--   guard, so none of the message functions has to learn about it. A person
--   reads their own (RLS), up to 20 per chat, for a day.
-- * bot_callbacks: where a bot wants presses sent (https only, no inner
--   addresses) and the secret that signs them. Closed to clients; the circle's
--   managers set it through functions (part 5).

-- ---------------------------------------------------------------- the column

alter table public.messages
  add column if not exists components jsonb;

alter table public.messages
  drop constraint if exists messages_components_array;
alter table public.messages
  add constraint messages_components_array check (
    components is null or (
      jsonb_typeof(components) = 'array'
      and jsonb_array_length(components) between 1 and 5
      and octet_length(components::text) <= 8192
    )
  );

-- ------------------------------------------------------------------- checking

-- A short text for a label, a placeholder or a title: a string, trimmed,
-- [min_length] to [max_length] characters, with no control characters (a new
-- line included) and nothing that reorders or hides text (bidirectional
-- controls, zero-width characters, the byte order mark).
create or replace function public.components_clean_text(
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
    cleaned := btrim(raw #>> '{}');
  end if;

  if char_length(cleaned) < min_length or char_length(cleaned) > max_length then
    raise exception '% must be % to % characters', field_name, min_length, max_length
      using errcode = '22023';
  end if;

  if cleaned ~ '[[:cntrl:]\u200b-\u200f\u202a-\u202e\u2060-⁤\u2066-\u2069\ufeff]' then
    raise exception '% has characters that are not allowed', field_name
      using errcode = '22023';
  end if;

  return cleaned;
end;
$$;

-- A link a button may open: https only, a real host name with a letter
-- in its last part (no address, no "localhost"), the default port, no
-- user name or password, no spaces, quotes, angle brackets or backslashes.
create or replace function public.components_https_url_ok(candidate text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select candidate is not null
    and char_length(candidate) <= 500
    and candidate ~* '^https://([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9](:443)?([/?#][^[:space:][:cntrl:]"<>`\\]*)?$'
    and candidate !~* '^https://[^/?#]*\.(local|localhost|localdomain|internal|lan|home|corp|intranet|private|arpa)(:443)?([/?#]|$)';
$$;

create or replace function public.components_id_ok(candidate text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select candidate ~ '^[A-Za-z0-9_.:-]{1,64}$';
$$;

-- The form a button opens: 1 to 5 fields.
create or replace function public.normalize_component_modal(raw jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  field jsonb;
  fields_out jsonb := '[]'::jsonb;
  seen text[] := '{}';
  field_id text;
  field_style text;
  max_chars integer;
  placeholder text;
begin
  if jsonb_typeof(raw) <> 'object' then
    raise exception 'A form must be an object' using errcode = '22023';
  end if;
  if jsonb_typeof(raw->'fields') is distinct from 'array'
    or jsonb_array_length(raw->'fields') not between 1 and 5
  then
    raise exception 'A form has 1 to 5 fields' using errcode = '22023';
  end if;

  for field in select value from jsonb_array_elements(raw->'fields') loop
    if jsonb_typeof(field) <> 'object' then
      raise exception 'A form field must be an object' using errcode = '22023';
    end if;
    field_id := field->>'id';
    if field_id is null or not public.components_id_ok(field_id) then
      raise exception 'A form field needs an id of letters, digits and _ . : -'
        using errcode = '22023';
    end if;
    if field_id = any (seen) then
      raise exception 'Form field ids must be different' using errcode = '22023';
    end if;
    seen := seen || field_id;

    field_style := coalesce(field->>'style', 'short');
    if field_style not in ('short', 'paragraph') then
      raise exception 'A form field is short or paragraph' using errcode = '22023';
    end if;

    if field ? 'max_length' and jsonb_typeof(field->'max_length') is distinct from 'number' then
      raise exception 'max_length must be a number' using errcode = '22023';
    end if;
    max_chars := coalesce((field->>'max_length')::numeric, 200)::integer;
    if max_chars not between 1 and 1000 then
      raise exception 'max_length is 1 to 1000' using errcode = '22023';
    end if;

    if field ? 'required' and jsonb_typeof(field->'required') is distinct from 'boolean' then
      raise exception 'required must be true or false' using errcode = '22023';
    end if;

    placeholder := case
      when field ? 'placeholder' and jsonb_typeof(field->'placeholder') <> 'null'
        then public.components_clean_text(field->'placeholder', 'A form placeholder', 0, 100)
      else ''
    end;

    fields_out := fields_out || jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object(
        'id', field_id,
        'label', public.components_clean_text(field->'label', 'A form label', 1, 45),
        'style', field_style,
        'required', coalesce((field->>'required')::boolean, true),
        'placeholder', nullif(placeholder, ''),
        'max_length', max_chars
      ))
    );
  end loop;

  return jsonb_build_object(
    'title', public.components_clean_text(raw->'title', 'A form title', 1, 45),
    'fields', fields_out
  );
end;
$$;

-- What a bot may attach to a message, cleaned: raises 22023 saying what is
-- wrong, returns null for nothing (null, 'null' or an empty list).
create or replace function public.normalize_message_components(raw jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  row_in jsonb;
  item jsonb;
  item_type text;
  item_id text;
  row_out jsonb;
  rows_out jsonb := '[]'::jsonb;
  seen text[] := '{}';
  total integer := 0;
  style text;
  built jsonb;
  option jsonb;
  options_out jsonb;
  option_values text[];
  option_value text;
  option_count integer;
  min_values integer;
  max_values integer;
  option_description text;
begin
  if raw is null or jsonb_typeof(raw) = 'null' then
    return null;
  end if;
  if jsonb_typeof(raw) <> 'array' then
    raise exception 'components must be a list of rows' using errcode = '22023';
  end if;
  if jsonb_array_length(raw) = 0 then
    return null;
  end if;
  if jsonb_array_length(raw) > 5 then
    raise exception 'At most 5 rows of components' using errcode = '22023';
  end if;

  for row_in in select value from jsonb_array_elements(raw) loop
    if jsonb_typeof(row_in) <> 'array'
      or jsonb_array_length(row_in) not between 1 and 5
    then
      raise exception 'A row holds 1 to 5 components' using errcode = '22023';
    end if;
    row_out := '[]'::jsonb;

    for item in select value from jsonb_array_elements(row_in) loop
      if jsonb_typeof(item) <> 'object' then
        raise exception 'A component must be an object' using errcode = '22023';
      end if;
      total := total + 1;
      item_type := item->>'type';

      if item_type in ('button', 'select') then
        item_id := item->>'id';
        if item_id is null or not public.components_id_ok(item_id) then
          raise exception 'A component needs an id of letters, digits and _ . : - (up to 64)'
            using errcode = '22023';
        end if;
        if item_id = any (seen) then
          raise exception 'Component ids must be different' using errcode = '22023';
        end if;
        seen := seen || item_id;
        if item ? 'disabled' and jsonb_typeof(item->'disabled') is distinct from 'boolean' then
          raise exception 'disabled must be true or false' using errcode = '22023';
        end if;
      end if;

      if item_type = 'button' then
        style := coalesce(item->>'style', 'secondary');
        if style not in ('primary', 'secondary', 'danger') then
          raise exception 'A button is primary, secondary or danger' using errcode = '22023';
        end if;
        built := jsonb_build_object(
          'type', 'button',
          'id', item_id,
          'label', public.components_clean_text(item->'label', 'A button label', 1, 40),
          'style', style
        );
        if coalesce((item->>'disabled')::boolean, false) then
          built := built || '{"disabled": true}'::jsonb;
        end if;
        if item ? 'modal' and jsonb_typeof(item->'modal') <> 'null' then
          built := built || jsonb_build_object(
            'modal', public.normalize_component_modal(item->'modal')
          );
        end if;
      elsif item_type = 'link' then
        if jsonb_typeof(item->'url') is distinct from 'string'
          or not public.components_https_url_ok(item->>'url')
        then
          raise exception 'A link button needs an https address of a website (no addresses, no other ports, up to 500 characters)'
            using errcode = '22023';
        end if;
        built := jsonb_build_object(
          'type', 'link',
          'label', public.components_clean_text(item->'label', 'A link label', 1, 40),
          'url', item->>'url'
        );
      elsif item_type = 'select' then
        if jsonb_typeof(item->'options') is distinct from 'array'
          or jsonb_array_length(item->'options') not between 1 and 25
        then
          raise exception 'A list has 1 to 25 options' using errcode = '22023';
        end if;
        options_out := '[]'::jsonb;
        option_values := '{}';
        for option in select value from jsonb_array_elements(item->'options') loop
          if jsonb_typeof(option) <> 'object' then
            raise exception 'An option must be an object' using errcode = '22023';
          end if;
          option_value := public.components_clean_text(option->'value', 'An option value', 1, 100);
          if option_value = any (option_values) then
            raise exception 'Option values must be different' using errcode = '22023';
          end if;
          option_values := option_values || option_value;
          option_description := case
            when option ? 'description' and jsonb_typeof(option->'description') <> 'null'
              then public.components_clean_text(option->'description', 'An option description', 0, 100)
            else ''
          end;
          if option ? 'default' and jsonb_typeof(option->'default') is distinct from 'boolean' then
            raise exception 'default must be true or false' using errcode = '22023';
          end if;
          options_out := options_out || jsonb_build_array(jsonb_strip_nulls(
            jsonb_build_object(
              'label', public.components_clean_text(option->'label', 'An option label', 1, 100),
              'value', option_value,
              'description', nullif(option_description, ''),
              'default', case when coalesce((option->>'default')::boolean, false) then true end
            )
          ));
        end loop;
        option_count := jsonb_array_length(options_out);

        if (item ? 'min_values' and jsonb_typeof(item->'min_values') is distinct from 'number')
          or (item ? 'max_values' and jsonb_typeof(item->'max_values') is distinct from 'number')
        then
          raise exception 'min_values and max_values must be numbers' using errcode = '22023';
        end if;
        min_values := coalesce((item->>'min_values')::numeric, 1)::integer;
        max_values := coalesce((item->>'max_values')::numeric, 1)::integer;
        if min_values < 0 or max_values < 1 or max_values > option_count
          or min_values > max_values
        then
          raise exception 'A list needs min_values 0 or more and max_values from 1 to the number of options'
            using errcode = '22023';
        end if;
        if (
          select count(*) from jsonb_array_elements(options_out) o
          where (o.value->>'default') = 'true'
        ) > max_values then
          raise exception 'More default options than max_values' using errcode = '22023';
        end if;

        built := jsonb_strip_nulls(jsonb_build_object(
          'type', 'select',
          'id', item_id,
          'placeholder', nullif(
            case
              when item ? 'placeholder' and jsonb_typeof(item->'placeholder') <> 'null'
                then public.components_clean_text(item->'placeholder', 'A placeholder', 0, 100)
              else ''
            end, ''),
          'options', options_out,
          'min_values', min_values,
          'max_values', max_values
        ));
        if coalesce((item->>'disabled')::boolean, false) then
          built := built || '{"disabled": true}'::jsonb;
        end if;
      else
        raise exception 'A component is a button, a link or a select' using errcode = '22023';
      end if;

      row_out := row_out || jsonb_build_array(built);
    end loop;

    -- A list takes a whole row.
    if exists (
      select 1 from jsonb_array_elements(row_out) c where c.value->>'type' = 'select'
    ) and jsonb_array_length(row_out) > 1 then
      raise exception 'A list takes a whole row' using errcode = '22023';
    end if;

    rows_out := rows_out || jsonb_build_array(row_out);
  end loop;

  if total > 25 then
    raise exception 'At most 25 components' using errcode = '22023';
  end if;
  if octet_length(rows_out::text) > 8192 then
    raise exception 'The components are too big (8 KB at most)' using errcode = '22023';
  end if;
  return rows_out;
end;
$$;

-- Every text a person reads in components, in one string, so AutoMod can
-- look at it.
create or replace function public.message_components_text(components jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(string_agg(t, E'\n'), '')
  from (
    select c.value->>'label' as t
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c
    union all
    select c.value->>'placeholder'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c
    union all
    select o.value->>'label'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c,
      jsonb_array_elements(coalesce(c.value->'options', '[]'::jsonb)) o
    union all
    select o.value->>'description'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c,
      jsonb_array_elements(coalesce(c.value->'options', '[]'::jsonb)) o
    union all
    select c.value#>>'{modal,title}'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c
    union all
    select f.value->>'label'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c,
      jsonb_array_elements(coalesce(c.value#>'{modal,fields}', '[]'::jsonb)) f
    union all
    select f.value->>'placeholder'
    from jsonb_array_elements(coalesce(components, '[]'::jsonb)) r,
      jsonb_array_elements(r.value) c,
      jsonb_array_elements(coalesce(c.value#>'{modal,fields}', '[]'::jsonb)) f
  ) texts
  where t is not null and t <> '';
$$;

revoke execute on function public.components_clean_text(jsonb, text, integer, integer) from public, anon, authenticated;
revoke execute on function public.components_https_url_ok(text) from public, anon, authenticated;
revoke execute on function public.components_id_ok(text) from public, anon, authenticated;
revoke execute on function public.normalize_component_modal(jsonb) from public, anon, authenticated;
revoke execute on function public.normalize_message_components(jsonb) from public, anon, authenticated;
revoke execute on function public.message_components_text(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------------ the guard

-- Components are the server's: a signed-in person's own insert or update never
-- sets them (current_user is then authenticated or anon), and only a bot's
-- plain text message can have them, so a bot cannot dress a system line, a
-- poll or a webhook post up with buttons. The bot functions hand them to the
-- insert through the setting wecord.message_components (the message is stored
-- with its components in one write, so no one sees it without them); they are
-- cleaned again here. Deleting a message drops its components.
create or replace function public.messages_guard_components()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  pending text;
begin
  if tg_op = 'INSERT' and new.components is null then
    pending := nullif(current_setting('wecord.message_components', true), '');
    if pending is not null then
      new.components := pending::jsonb;
    end if;
  end if;

  if new.components is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.components is not distinct from old.components then
    if new.recalled_at is not null then
      new.components := null;
    end if;
    return new;
  end if;

  if current_user in ('authenticated', 'anon') then
    raise exception 'Components are set by the server' using errcode = '42501';
  end if;

  if new.recalled_at is not null then
    new.components := null;
    return new;
  end if;

  if new.type <> 'text'
    or new.webhook_id is not null
    or new.webhook_name is not null
    or new.forwarded_from is not null
    or new.crosspost is not null
    or not exists (
      select 1
      from public.circle_bots b
      where b.user_id = new.sender_id
    )
  then
    raise exception 'Only a bot''s own text message can have components'
      using errcode = '42501';
  end if;

  new.components := public.normalize_message_components(new.components);
  return new;
end;
$$;

revoke execute on function public.messages_guard_components() from public, anon, authenticated;

drop trigger if exists messages_guard_components on public.messages;
create trigger messages_guard_components
  before insert or update on public.messages
  for each row
  when (new.components is not null or current_setting('wecord.message_components', true) <> '')
  execute function public.messages_guard_components();

-- ------------------------------------------------------- private replies table

create table if not exists public.bot_ephemeral_messages (
  id uuid primary key default gen_random_uuid(),
  bot_id uuid not null references public.circle_bots(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  -- The message the person pressed on (null for a command).
  message_id uuid references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  interaction_id uuid,
  body text not null,
  components jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '1 day',
  constraint bot_ephemeral_body_length check (char_length(body) between 1 and 2000),
  constraint bot_ephemeral_components_array check (
    components is null or (
      jsonb_typeof(components) = 'array'
      and octet_length(components::text) <= 8192
    )
  )
);

create index if not exists bot_ephemeral_user_idx
  on public.bot_ephemeral_messages (user_id, conversation_id, created_at desc);
create index if not exists bot_ephemeral_message_idx
  on public.bot_ephemeral_messages (message_id);
create index if not exists bot_ephemeral_expiry_idx
  on public.bot_ephemeral_messages (expires_at);

alter table public.bot_ephemeral_messages enable row level security;
revoke all on public.bot_ephemeral_messages from public, anon, authenticated;
grant select on public.bot_ephemeral_messages to authenticated;

-- A person reads only their own, and only where they can still read the chat
-- (membership, channel permission, a suspended circle: the same function the
-- messages' policy uses).
drop policy if exists bot_ephemeral_select_own on public.bot_ephemeral_messages;
create policy bot_ephemeral_select_own
  on public.bot_ephemeral_messages for select
  to authenticated
  using (
    user_id = auth.uid()
    and expires_at > now()
    and conversation_id in (select public.current_user_readable_conversation_ids())
  );

-- At most 20 private replies per person and chat: the newest stay.
create or replace function public.bot_ephemeral_keep_newest()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.bot_ephemeral_messages e
  where e.user_id = new.user_id
    and e.conversation_id = new.conversation_id
    and e.id in (
      select old_rows.id
      from public.bot_ephemeral_messages old_rows
      where old_rows.user_id = new.user_id
        and old_rows.conversation_id = new.conversation_id
      order by old_rows.created_at desc, old_rows.id desc
      offset 20
    );
  return null;
end;
$$;

revoke execute on function public.bot_ephemeral_keep_newest() from public, anon, authenticated;

drop trigger if exists bot_ephemeral_keep_newest on public.bot_ephemeral_messages;
create trigger bot_ephemeral_keep_newest
  after insert on public.bot_ephemeral_messages
  for each row execute function public.bot_ephemeral_keep_newest();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'bot_ephemeral_messages'
    )
  then
    alter publication supabase_realtime add table public.bot_ephemeral_messages;
  end if;
end $$;

-- ----------------------------------------------------- bot_interactions grows

alter table public.bot_interactions
  add column if not exists kind text not null default 'command',
  add column if not exists message_id uuid references public.messages(id) on delete cascade,
  add column if not exists ephemeral_id uuid references public.bot_ephemeral_messages(id) on delete cascade,
  add column if not exists component_id text,
  add column if not exists component_type text,
  add column if not exists component_label text,
  add column if not exists submitted jsonb,
  add column if not exists response_kind text,
  add column if not exists delivery_state text not null default 'none',
  add column if not exists delivery_attempts integer not null default 0,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists delivered_at timestamptz,
  add column if not exists delivery_error text;

alter table public.bot_interactions
  alter column command_name drop not null;

alter table public.bot_interactions
  drop constraint if exists bot_interactions_kind_check,
  drop constraint if exists bot_interactions_shape_check,
  drop constraint if exists bot_interactions_delivery_check,
  drop constraint if exists bot_interactions_response_kind_check,
  drop constraint if exists bot_interactions_submitted_size;

alter table public.bot_interactions
  add constraint bot_interactions_kind_check check (kind in ('command', 'component')),
  add constraint bot_interactions_shape_check check (
    (kind = 'command' and command_name is not null)
    or (
      kind = 'component'
      and component_id is not null
      and (message_id is not null or ephemeral_id is not null)
    )
  ),
  add constraint bot_interactions_delivery_check check (
    delivery_state in ('none', 'queued', 'sending', 'delivered', 'failed')
  ),
  add constraint bot_interactions_response_kind_check check (
    response_kind is null or response_kind in ('message', 'ephemeral', 'update', 'ack')
  ),
  add constraint bot_interactions_submitted_size check (
    submitted is null or octet_length(submitted::text) <= 8192
  );

create index if not exists bot_interactions_message_idx
  on public.bot_interactions (message_id)
  where message_id is not null;
create index if not exists bot_interactions_delivery_idx
  on public.bot_interactions (next_attempt_at)
  where delivery_state in ('queued', 'sending');
create index if not exists bot_interactions_kind_user_idx
  on public.bot_interactions (user_id, created_at)
  where kind = 'component';

-- ----------------------------------------------------------- callback settings

create table if not exists public.bot_callbacks (
  bot_id uuid primary key references public.circle_bots(id) on delete cascade,
  url text not null,
  secret text not null,
  enabled boolean not null default true,
  consecutive_failures integer not null default 0,
  last_status integer,
  last_error text,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bot_callbacks_url_length check (char_length(url) <= 500),
  constraint bot_callbacks_secret_format check (secret ~ '^[0-9a-f]{64}$')
);

alter table public.bot_callbacks enable row level security;
revoke all on public.bot_callbacks from public, anon, authenticated;
