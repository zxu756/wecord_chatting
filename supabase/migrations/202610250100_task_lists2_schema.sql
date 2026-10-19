-- Task lists 2.0 (D7), part 1: the schema.
--
-- * task_lists.field_defs: the list's own fields, an ordered array of up to
--   20 {id, name, type, options?}. type is 'number', 'select' (options is an
--   array of up to 30 {id, name}), 'link' or 'person'.
-- * task_items.custom: the values, an object {field id: value}. A number is
--   a JSON number, a select the id of one of its options, a link an http(s)
--   address, a person a user id. Values are checked against the list's
--   fields when written; ones that no longer fit (the field is gone, its
--   type changed, its option was removed) are dropped, never an error, so
--   old rows and queued offline patches keep working.
-- * task_items.parent_id: a subtask belongs to a task of the same list. One
--   level only: a subtask has no subtasks.
-- * task_items.recurrence: {freq: daily|weekly|monthly|yearly, interval:
--   1..99, tz?, tz_offset?, anchor_day?} or null. Finishing a repeating task
--   makes the next one (see the trigger in 202610250120).
-- * task_items.next_item_id: the task made when this one was finished, so
--   unchecking and checking it again never makes a second one.
--
-- Old rows get '[]' / '{}' / null, so nothing existing changes.

alter table public.task_lists
  add column if not exists field_defs jsonb not null default '[]'::jsonb;

alter table public.task_items
  add column if not exists custom jsonb not null default '{}'::jsonb,
  add column if not exists parent_id uuid references public.task_items(id) on delete cascade,
  add column if not exists recurrence jsonb,
  add column if not exists next_item_id uuid;

alter table public.task_items drop constraint if exists task_items_custom_shape;
alter table public.task_items
  add constraint task_items_custom_shape check (jsonb_typeof(custom) = 'object');
alter table public.task_items drop constraint if exists task_items_not_own_parent;
alter table public.task_items
  add constraint task_items_not_own_parent check (parent_id is null or parent_id <> id);

create index if not exists task_items_parent_idx
  on public.task_items (parent_id)
  where parent_id is not null and deleted_at is null;

-- ----------------------------------------------------------------- fields

-- Whether [value] is a usable list of fields.
create or replace function public.valid_task_field_defs(value jsonb)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  entry jsonb;
  option jsonb;
  ids text[] := array[]::text[];
  option_ids text[];
begin
  if value is null or jsonb_typeof(value) <> 'array'
    or jsonb_array_length(value) > 20
  then
    return false;
  end if;
  for entry in select * from jsonb_array_elements(value) loop
    if jsonb_typeof(entry) <> 'object'
      or coalesce(entry->>'id', '') !~ '^[a-z0-9_-]{1,32}$'
      or char_length(btrim(coalesce(entry->>'name', ''))) not between 1 and 40
      or coalesce(entry->>'type', '') not in ('number', 'select', 'link', 'person')
      or (entry->>'id') = any (ids)
    then
      return false;
    end if;
    ids := ids || (entry->>'id');
    if entry->>'type' = 'select' then
      if coalesce(jsonb_typeof(entry->'options'), '') <> 'array'
        or jsonb_array_length(entry->'options') > 30
      then
        return false;
      end if;
      option_ids := array[]::text[];
      for option in select * from jsonb_array_elements(entry->'options') loop
        if jsonb_typeof(option) <> 'object'
          or coalesce(option->>'id', '') !~ '^[a-z0-9_-]{1,32}$'
          or char_length(btrim(coalesce(option->>'name', ''))) not between 1 and 40
          or (option->>'id') = any (option_ids)
        then
          return false;
        end if;
        option_ids := option_ids || (option->>'id');
      end loop;
    end if;
  end loop;
  return true;
end;
$$;

-- [value] cut down to the keys the app knows, in the order given.
create or replace function public.normalize_task_field_defs(value jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_agg(
    case
      when d.entry->>'type' = 'select' then jsonb_build_object(
        'id', d.entry->>'id',
        'name', btrim(d.entry->>'name'),
        'type', 'select',
        'options', coalesce((
          select jsonb_agg(jsonb_build_object('id', o->>'id', 'name', btrim(o->>'name')) order by oo.n)
          from jsonb_array_elements(d.entry->'options') with ordinality oo(o, n)
        ), '[]'::jsonb)
      )
      else jsonb_build_object(
        'id', d.entry->>'id',
        'name', btrim(d.entry->>'name'),
        'type', d.entry->>'type'
      )
    end
    order by d.n
  ), '[]'::jsonb)
  from jsonb_array_elements(value) with ordinality d(entry, n);
$$;

-- [value] as the field [def] holds it, or null when it does not fit.
create or replace function public.coerce_task_field_value(def jsonb, value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  text_value text;
  number_value numeric;
begin
  if def is null or value is null or jsonb_typeof(value) = 'null' then
    return null;
  end if;
  case def->>'type'
    when 'number' then
      if jsonb_typeof(value) = 'number' then
        number_value := (value #>> '{}')::numeric;
      elsif jsonb_typeof(value) = 'string'
        and (value #>> '{}') ~ '^\s*-?[0-9]{1,15}(\.[0-9]{1,6})?\s*$'
      then
        number_value := btrim(value #>> '{}')::numeric;
      else
        return null;
      end if;
      if abs(number_value) > 1000000000000 then
        return null;
      end if;
      return to_jsonb(number_value);
    when 'select' then
      if jsonb_typeof(value) <> 'string' then
        return null;
      end if;
      text_value := value #>> '{}';
      if exists (
        select 1 from jsonb_array_elements(def->'options') o where o->>'id' = text_value
      ) then
        return to_jsonb(text_value);
      end if;
      return null;
    when 'link' then
      if jsonb_typeof(value) <> 'string' then
        return null;
      end if;
      text_value := btrim(value #>> '{}');
      if char_length(text_value) <= 500 and text_value ~* '^https?://[^[:space:]]+$' then
        return to_jsonb(text_value);
      end if;
      return null;
    when 'person' then
      if jsonb_typeof(value) <> 'string' then
        return null;
      end if;
      text_value := lower(value #>> '{}');
      if text_value ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        return to_jsonb(text_value);
      end if;
      return null;
    else
      return null;
  end case;
end;
$$;

-- The entries of [custom] that still fit the fields [defs].
create or replace function public.task_clean_custom(defs jsonb, custom jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from jsonb_each(case when jsonb_typeof(custom) = 'object' then custom else '{}'::jsonb end) e
  where exists (
    select 1
    from jsonb_array_elements(defs) d
    where d->>'id' = e.key
      and public.coerce_task_field_value(d, e.value) is not null
  );
$$;

-- ------------------------------------------------------------ recurrence

-- [value] as a repeat rule, or an error when it is not one.
create or replace function public.normalize_task_recurrence(value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  freq text;
  every integer;
  offset_minutes integer;
  anchor integer;
  zone text;
begin
  if value is null or jsonb_typeof(value) <> 'object' then
    raise exception 'Invalid repeat' using errcode = '22023';
  end if;
  freq := value->>'freq';
  if freq is null or freq not in ('daily', 'weekly', 'monthly', 'yearly') then
    raise exception 'Invalid repeat' using errcode = '22023';
  end if;
  begin
    every := coalesce(nullif(value->>'interval', '')::integer, 1);
    offset_minutes := nullif(value->>'tz_offset', '')::integer;
    anchor := nullif(value->>'anchor_day', '')::integer;
  exception when others then
    raise exception 'Invalid repeat' using errcode = '22023';
  end;
  if every not between 1 and 99
    or (offset_minutes is not null and offset_minutes not between -840 and 840)
    or (anchor is not null and anchor not between 1 and 31)
  then
    raise exception 'Invalid repeat' using errcode = '22023';
  end if;
  zone := nullif(value->>'tz', '');
  if zone is not null and zone !~ '^[A-Za-z0-9_+./-]{1,64}$' then
    zone := null;
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'freq', freq,
    'interval', every,
    'tz', zone,
    'tz_offset', offset_minutes,
    'anchor_day', anchor
  ));
end;
$$;

-- The first date after [p_after] that the rule [p_rec] puts the task on,
-- counting from its date [p_due]. All-day tasks stay at the end of their
-- day. [p_zone] is an IANA time zone for working out the local day; without
-- one the rule's tz_offset (minutes east of UTC) is used. Months keep the
-- day they started on (the 31st is the last day of shorter months, then the
-- 31st again).
create or replace function public.task_next_due(
  p_due timestamptz,
  p_has_time boolean,
  p_rec jsonb,
  p_after timestamptz,
  p_zone text default null
)
returns timestamptz
language plpgsql
stable
set search_path = public
as $$
declare
  every integer := coalesce(nullif(p_rec->>'interval', '')::integer, 1);
  freq text := p_rec->>'freq';
  shift integer := coalesce(nullif(p_rec->>'tz_offset', '')::integer, 0);
  local_start timestamp;
  month_start timestamp;
  base_day integer;
  days_in_month integer;
  candidate timestamp;
  result timestamptz;
  step integer := 0;
begin
  if p_due is null or p_rec is null or freq is null then
    return null;
  end if;
  if p_zone is not null then
    local_start := p_due at time zone p_zone;
  else
    local_start := (p_due at time zone 'UTC') + make_interval(mins => shift);
  end if;
  base_day := coalesce(nullif(p_rec->>'anchor_day', '')::integer, extract(day from local_start)::integer);
  loop
    step := step + 1;
    candidate := case freq
      when 'daily' then local_start + make_interval(days => every * step)
      when 'weekly' then local_start + make_interval(days => 7 * every * step)
      when 'yearly' then local_start + make_interval(years => every * step)
      else null
    end;
    if freq = 'monthly' then
      month_start := date_trunc('month', local_start) + make_interval(months => every * step);
      days_in_month := extract(day from (month_start + interval '1 month' - interval '1 day'))::integer;
      candidate := month_start
        + make_interval(days => least(base_day, days_in_month) - 1)
        + local_start::time;
    end if;
    if not p_has_time then
      candidate := date_trunc('day', candidate) + time '23:59';
    end if;
    if p_zone is not null then
      result := candidate at time zone p_zone;
    else
      result := (candidate - make_interval(mins => shift)) at time zone 'UTC';
    end if;
    exit when result > p_after or step >= 3000;
  end loop;
  return result;
end;
$$;

revoke execute on function public.valid_task_field_defs(jsonb) from public, anon;
revoke execute on function public.normalize_task_field_defs(jsonb) from public, anon;
revoke execute on function public.coerce_task_field_value(jsonb, jsonb) from public, anon;
revoke execute on function public.task_clean_custom(jsonb, jsonb) from public, anon;
revoke execute on function public.normalize_task_recurrence(jsonb) from public, anon;
revoke execute on function public.task_next_due(timestamptz, boolean, jsonb, timestamptz, text) from public, anon;
grant execute on function public.valid_task_field_defs(jsonb) to authenticated;
grant execute on function public.normalize_task_field_defs(jsonb) to authenticated;
grant execute on function public.coerce_task_field_value(jsonb, jsonb) to authenticated;
grant execute on function public.task_clean_custom(jsonb, jsonb) to authenticated;
grant execute on function public.normalize_task_recurrence(jsonb) to authenticated;
grant execute on function public.task_next_due(timestamptz, boolean, jsonb, timestamptz, text) to authenticated;

alter table public.task_lists drop constraint if exists task_lists_field_defs_valid;
alter table public.task_lists
  add constraint task_lists_field_defs_valid check (public.valid_task_field_defs(field_defs));

-- ------------------------------------------------------------------ JSON

-- Based on 202610170062_task_lists.sql: adds field_defs.
create or replace function public.task_list_json(l public.task_lists)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', l.id,
    'conversation_id', l.conversation_id,
    'title', l.title,
    'icon', l.icon,
    'statuses', l.statuses,
    'field_defs', l.field_defs,
    'default_view', l.default_view,
    'created_by', l.created_by,
    'created_at', l.created_at,
    'updated_at', l.updated_at,
    'can_edit', public.can_current_user_edit_task_list(l.id),
    'can_manage', public.can_current_user_manage_task_list(l.id)
  );
$$;

-- Based on 202610170062_task_lists.sql: adds custom, parent_id, recurrence.
create or replace function public.task_item_json(i public.task_items)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', i.id,
    'list_id', i.list_id,
    'title', i.title,
    'details', i.details,
    'status', i.status,
    'priority', i.priority,
    'due_at', i.due_at,
    'due_has_time', i.due_has_time,
    'pos', i.pos,
    'source_message_id', i.source_message_id,
    'created_by', i.created_by,
    'created_at', i.created_at,
    'updated_at', i.updated_at,
    'completed_at', i.completed_at,
    'deleted', i.deleted_at is not null,
    'custom', i.custom,
    'parent_id', i.parent_id,
    'recurrence', i.recurrence,
    'assignees', coalesce((
      select jsonb_agg(a.user_id order by a.assigned_at, a.user_id)
      from public.task_item_assignees a
      where a.item_id = i.id
    ), '[]'::jsonb)
  );
$$;

revoke execute on function public.task_list_json(public.task_lists) from public, anon, authenticated;
revoke execute on function public.task_item_json(public.task_items) from public, anon, authenticated;
