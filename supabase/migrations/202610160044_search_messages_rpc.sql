-- Message search, part 2: search_messages with filters, scopes, sorting
-- and keyset pages, and the messages around a result.
--
-- search_messages(query, filters, scope, sort, max_results, cursor) only
-- looks at conversations in current_user_readable_conversation_ids() (the
-- set the messages select policy uses), narrowed to the scope:
--   scope {"type": "everywhere"} | {"type": "circle", "id": circle} |
--         {"type": "conversation", "id": conversation}
-- A conversation or circle includes its threads. The query is free text:
-- words and "quoted phrases" must all match, -word and -"phrase" must not.
-- A term matches through the full-text vector (whole words, any run of
-- CJK characters) or, from three characters, as a substring through the
-- trigram index. Filters (all optional):
--   from, mentions: profile ids; in: conversation ids (and their threads);
--   has: any of image, video, file, voice, poll, sticker, link (all must
--   hold); before, after, during: an ISO timestamp, or a YYYY-MM-DD day
--   read at utc_offset_minutes (default 0): before a day is before it
--   starts, after a day is after it ends, during is that day; pinned:
--   true or false.
-- sort: newest (default), oldest or relevance. Pages of max_results
-- (1..50, default 25); pass back next_cursor for the next one. The first
-- page also counts matches, up to 1000, in all and per conversation.
--
-- The query is assembled from only the filters given (format with %L
-- literals) so every search gets a plan for its own conditions.

-- Profile, conversation and circle ids in a jsonb array; anything that is
-- not a uuid is ignored.
create or replace function public.search_uuid_array(value jsonb)
returns uuid[]
language sql
immutable
parallel safe
as $$
  select coalesce(array_agg(distinct item::uuid), '{}'::uuid[])
  from jsonb_array_elements_text(
    case jsonb_typeof(value)
      when 'array' then value
      when 'string' then jsonb_build_array(value)
      else '[]'::jsonb
    end
  ) item
  where item ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

-- The conversations in [search_scope] the caller can read, with the
-- threads of the conversations named.
create or replace function public.search_scope_conversation_ids(search_scope jsonb)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  scope_type text := coalesce(search_scope->>'type', 'everywhere');
  scope_ids uuid[] := public.search_uuid_array(search_scope->'id');
  result uuid[];
begin
  if scope_type not in ('everywhere', 'circle', 'conversation') then
    raise exception 'Unknown search scope %', scope_type
      using errcode = '22023';
  end if;
  if scope_type <> 'everywhere' and cardinality(scope_ids) = 0 then
    return '{}'::uuid[];
  end if;

  select coalesce(array_agg(r.id), '{}'::uuid[])
  into result
  from public.current_user_readable_conversation_ids() r(id)
  where scope_type = 'everywhere'
    or (
      scope_type = 'conversation'
      and (
        r.id = any(scope_ids)
        or exists (
          select 1
          from public.conversation_threads ct
          where ct.conversation_id = r.id
            and ct.parent_conversation_id = any(scope_ids)
        )
      )
    )
    or (
      scope_type = 'circle'
      and exists (
        select 1
        from public.circle_channels cc
        left join public.conversation_threads ct
          on ct.parent_conversation_id = cc.conversation_id
        where cc.circle_id = any(scope_ids)
          and r.id in (cc.conversation_id, ct.conversation_id)
      )
    );
  return result;
end;
$$;

-- The start of [day_text] at [offset_minutes] east of UTC, or the
-- timestamp itself; null for anything else.
create or replace function public.search_filter_instant(
  value_text text,
  offset_minutes integer,
  day_shift integer
)
returns timestamptz
language plpgsql
stable
as $$
begin
  if value_text is null or btrim(value_text) = '' then
    return null;
  end if;
  if value_text ~ '^\d{4}-\d{2}-\d{2}$' then
    return (
      (value_text::date + day_shift)::timestamp
      - make_interval(mins => coalesce(offset_minutes, 0))
    ) at time zone 'UTC';
  end if;
  return value_text::timestamptz;
exception
  when others then
    raise exception 'Invalid search date %', value_text using errcode = '22007';
end;
$$;

-- A message as search results and context show it.
create or replace function public.search_message_json(
  target public.messages,
  rank real,
  caller uuid
)
returns jsonb
language plpgsql
stable
as $$
begin
  return (
    select jsonb_build_object(
        'id', target.id,
        'conversation_id', target.conversation_id,
        'sender_id', target.sender_id,
        'sender_name', coalesce(
          nullif(btrim(coalesce(target.webhook_name, '')), ''),
          nullif(btrim(coalesce(ca.alias, '')), ''),
          sender.display_name
        ),
        'sender_avatar_url', coalesce(target.webhook_avatar_url, sender.avatar_url),
        'type', target.type,
        'body', target.body,
        'attachment', target.attachment,
        'created_at', target.created_at,
        'edited_at', target.edited_at,
        'rank', rank,
        'pinned', exists (
          select 1 from public.pinned_messages pm where pm.message_id = target.id
        )
      )
      from (select 1) one
      left join public.profiles sender on sender.id = target.sender_id
      left join public.contact_aliases ca
        on ca.owner_id = caller
        and ca.friend_id = target.sender_id
  );
end;
$$;

-- Where a message lives, for result group headers.
create or replace function public.search_conversation_json(
  target_conversation_id uuid,
  caller uuid
)
returns jsonb
language plpgsql
stable
as $$
begin
  return (
    select jsonb_build_object(
        'id', c.id,
        'type', c.type,
        'title', case
          when c.type = 'direct' then coalesce(
            nullif(btrim(coalesce(peer_alias.alias, '')), ''),
            peer.display_name,
            c.title
          )
          when c.type = 'channel' then coalesce(channel.name, c.title)
          when c.type = 'thread' then coalesce(thread.title, c.title)
          else c.title
        end,
        'avatar_url', case
          when c.type = 'direct' then peer.avatar_url
          when c.type in ('channel', 'thread') then circle.avatar_url
          else c.avatar_url
        end,
        'direct_user_id', peer.id,
        'circle_id', circle.id,
        'circle_name', circle.name,
        'channel_kind', coalesce(channel.kind, parent_channel.kind),
        'parent_conversation_id', thread.parent_conversation_id,
        'parent_title', coalesce(parent_channel.name, parent.title)
      )
      from public.conversations c
      left join public.conversation_threads thread
        on thread.conversation_id = c.id
      left join public.conversations parent
        on parent.id = thread.parent_conversation_id
      left join public.circle_channels channel
        on channel.conversation_id = c.id
      left join public.circle_channels parent_channel
        on parent_channel.conversation_id = thread.parent_conversation_id
      left join public.circles circle
        on circle.id = coalesce(channel.circle_id, parent_channel.circle_id)
      left join lateral (
        select cm.user_id
        from public.conversation_members cm
        where c.type = 'direct'
          and cm.conversation_id = c.id
          and cm.user_id <> caller
        limit 1
      ) peer_member on true
      left join public.profiles peer on peer.id = peer_member.user_id
      left join public.contact_aliases peer_alias
        on peer_alias.owner_id = caller
        and peer_alias.friend_id = peer.id
      where c.id = target_conversation_id
  );
end;
$$;

create or replace function public.search_messages(
  query text,
  filters jsonb,
  scope jsonb,
  sort text,
  max_results integer,
  cursor jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  search_text text := left(btrim(coalesce(query, '')), 256);
  f jsonb := coalesce(filters, '{}'::jsonb);
  sort_by text := coalesce(nullif(sort, ''), 'newest');
  page_size integer := least(greatest(coalesce(max_results, 25), 1), 50);
  conversation_ids uuid[];
  in_ids uuid[];
  from_ids uuid[];
  mention_ids uuid[];
  kinds text[];
  offset_minutes integer;
  lower_bound timestamptz;
  upper_bound timestamptz;
  vector_sql constant text := 'e.vector';
  document_sql constant text := 'e.document';
  conditions text := '';
  rank_query tsquery;
  rank_sql text := '0::real';
  term record;
  term_text text;
  term_query tsquery;
  term_condition text;
  has_criteria boolean := false;
  cursor_sql text := '';
  order_sql text;
  base_sql text;
  page jsonb;
  results jsonb := '[]'::jsonb;
  next_cursor jsonb;
  counts jsonb;
  places jsonb;
  total integer;
  row_count integer;
  last_row jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  if sort_by not in ('newest', 'oldest', 'relevance') then
    raise exception 'Unknown search sort %', sort_by using errcode = '22023';
  end if;

  conversation_ids := public.search_scope_conversation_ids(scope);

  in_ids := public.search_uuid_array(f->'in');
  if cardinality(in_ids) > 0 then
    has_criteria := true;
    conversation_ids := array(
      select unnest(conversation_ids)
      intersect
      select unnest(
        public.search_scope_conversation_ids(
          jsonb_build_object('type', 'conversation', 'id', to_jsonb(in_ids))
        )
      )
    );
  end if;

  if cardinality(conversation_ids) = 0 then
    return jsonb_build_object(
      'results', '[]'::jsonb,
      'next_cursor', null,
      'total', case when cursor is null then 0 end,
      'total_capped', false,
      'conversations', '[]'::jsonb
    );
  end if;

  -- Words and phrases.
  for term in
    select
      coalesce(match[1], match[3]) = '-' as negated,
      lower(btrim(coalesce(match[2], match[4]))) as text
    from regexp_matches(search_text, '(-?)"([^"]*)"?|(-?)(\S+)', 'g') match
  loop
    term_text := term.text;
    continue when term_text is null or term_text = '';
    term_query := phraseto_tsquery(
      'simple'::regconfig,
      public.search_split_cjk(term_text)
    );
    term_condition := null;
    if numnode(term_query) > 0 then
      term_condition := format('%s @@ %L::tsquery', vector_sql, term_query::text);
    end if;
    if char_length(term_text) >= 3 then
      term_condition := concat_ws(
        ' or ',
        term_condition,
        format(
          '%s like %L',
          document_sql,
          public.search_like_pattern(term_text)
        )
      );
    end if;
    continue when term_condition is null;
    if term.negated then
      conditions := conditions || format(' and not (%s)', term_condition);
    else
      has_criteria := true;
      conditions := conditions || format(' and (%s)', term_condition);
      if numnode(term_query) > 0 then
        rank_query := case
          when rank_query is null then term_query
          else rank_query && term_query
        end;
      end if;
    end if;
  end loop;

  -- Filters.
  from_ids := public.search_uuid_array(f->'from');
  if cardinality(from_ids) > 0 then
    has_criteria := true;
    conditions := conditions
      || format(' and e.sender_id = any(%L::uuid[])', from_ids);
  end if;

  mention_ids := public.search_uuid_array(f->'mentions');
  if cardinality(mention_ids) > 0 then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.message_id in (select mm.message_id from public.message_mentions mm'
      ' where mm.kind = ''user'' and mm.user_id = any(%L::uuid[]))',
      mention_ids
    );
  end if;

  select coalesce(array_agg(distinct k), '{}'::text[])
  into kinds
  from jsonb_array_elements_text(
    case jsonb_typeof(f->'has')
      when 'array' then f->'has'
      when 'string' then jsonb_build_array(f->'has')
      else '[]'::jsonb
    end
  ) k;
  if exists (
    select 1 from unnest(kinds) k
    where k not in ('image', 'video', 'file', 'voice', 'poll', 'sticker', 'link')
  ) then
    raise exception 'Unknown has: filter' using errcode = '22023';
  end if;
  if cardinality(kinds) > 0 then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.kinds @> %L::text[]',
      kinds
    );
  end if;

  offset_minutes := coalesce((f->>'utc_offset_minutes')::integer, 0);
  lower_bound := public.search_filter_instant(f->>'after', offset_minutes, 1);
  upper_bound := public.search_filter_instant(f->>'before', offset_minutes, 0);
  if f->>'during' is not null then
    lower_bound := greatest(
      lower_bound,
      public.search_filter_instant(f->>'during', offset_minutes, 0)
    );
    upper_bound := least(
      upper_bound,
      public.search_filter_instant(f->>'during', offset_minutes, 1)
    );
  end if;
  if lower_bound is not null then
    has_criteria := true;
    conditions := conditions
      || format(' and e.created_at >= %L::timestamptz', lower_bound);
  end if;
  if upper_bound is not null then
    has_criteria := true;
    conditions := conditions
      || format(' and e.created_at < %L::timestamptz', upper_bound);
  end if;

  if jsonb_typeof(f->'pinned') = 'boolean' then
    has_criteria := true;
    conditions := conditions || format(
      ' and e.message_id %s (select pm.message_id from public.pinned_messages pm'
      ' where pm.conversation_id = any($1))',
      case when (f->>'pinned')::boolean then 'in' else 'not in' end
    );
  end if;

  if not has_criteria then
    return jsonb_build_object(
      'results', '[]'::jsonb,
      'next_cursor', null,
      'total', case when cursor is null then 0 end,
      'total_capped', false,
      'conversations', '[]'::jsonb
    );
  end if;

  if sort_by = 'relevance' and rank_query is not null then
    rank_sql := format(
      'ts_rank_cd(%s, %L::tsquery)::real',
      vector_sql,
      rank_query::text
    );
  end if;

  base_sql := format(
    'select e.message_id as id, e.created_at, %s as search_rank'
    ' from public.message_search_entries e'
    ' where e.conversation_id = any($1)%s',
    rank_sql,
    conditions
  );

  if cursor is not null then
    cursor_sql := case sort_by
      when 'oldest' then format(
        ' where (r.created_at, r.id) > (%L::timestamptz, %L::uuid)',
        cursor->>'created_at', cursor->>'id'
      )
      when 'newest' then format(
        ' where (r.created_at, r.id) < (%L::timestamptz, %L::uuid)',
        cursor->>'created_at', cursor->>'id'
      )
      else format(
        ' where (r.search_rank, r.created_at, r.id)'
        ' < (%L::real, %L::timestamptz, %L::uuid)',
        coalesce(cursor->>'rank', '0'), cursor->>'created_at', cursor->>'id'
      )
    end;
  end if;
  order_sql := case sort_by
    when 'oldest' then 'r.created_at asc, r.id asc'
    when 'newest' then 'r.created_at desc, r.id desc'
    else 'r.search_rank desc, r.created_at desc, r.id desc'
  end;

  execute format(
    'select coalesce(jsonb_agg('
    '  public.search_message_json(m, r.search_rank, $2)'
    '  order by r.ordinal), ''[]''::jsonb)'
    ' from (select r.*, row_number() over (order by %s) as ordinal'
    '  from (select * from (%s) r%s order by %s limit %s) r) r'
    ' join public.messages m on m.id = r.id',
    order_sql,
    base_sql,
    cursor_sql,
    order_sql,
    page_size + 1
  ) into page using conversation_ids, caller;

  row_count := jsonb_array_length(page);
  if row_count > page_size then
    results := page - page_size;
    last_row := results->(page_size - 1);
    next_cursor := jsonb_build_object(
      'created_at', last_row->'created_at',
      'id', last_row->'id',
      'rank', last_row->'rank'
    );
  else
    results := page;
  end if;

  -- Where each result lives, once per conversation.
  select coalesce(
    jsonb_object_agg(id, public.search_conversation_json(id, caller)),
    '{}'::jsonb
  )
  into places
  from (
    select distinct (item->>'conversation_id')::uuid as id
    from jsonb_array_elements(results) item
  ) page_conversations;
  select coalesce(jsonb_agg(
    item || jsonb_build_object('conversation', places->(item->>'conversation_id'))
    order by ordinal
  ), '[]'::jsonb)
  into results
  from jsonb_array_elements(results) with ordinality as items(item, ordinal);

  if cursor is null then
    execute format(
      'select coalesce(sum(n), 0)::integer, coalesce(jsonb_agg(jsonb_build_object('
      '  ''conversation_id'', conversation_id, ''count'', n) order by n desc), ''[]''::jsonb)'
      ' from (select conversation_id, count(*) as n'
      '  from (select e.conversation_id from public.message_search_entries e'
      '   where e.conversation_id = any($1)%s limit 1001) capped'
      '  group by conversation_id) per_conversation',
      conditions
    ) into total, counts using conversation_ids;
  end if;

  return jsonb_build_object(
    'results', results,
    'next_cursor', next_cursor,
    'total', case when cursor is null then least(total, 1000) end,
    'total_capped', coalesce(total > 1000, false),
    'conversations', coalesce(counts, '[]'::jsonb)
  );
end;
$$;

-- The visible messages just before and after [target_message_id] in its
-- conversation, for a search result opened in place.
create or replace function public.search_message_context(
  target_message_id uuid,
  before_count integer,
  after_count integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  target public.messages;
  before_rows jsonb;
  after_rows jsonb;
begin
  if caller is null then
    raise exception 'Sign in to search messages' using errcode = '42501';
  end if;
  select m.* into target
  from public.messages m
  where m.id = target_message_id
    and m.conversation_id in (
      select public.current_user_readable_conversation_ids()
    );
  if target.id is null then
    return jsonb_build_object('before', '[]'::jsonb, 'after', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(public.search_message_json(b, 0, caller)
    order by b.created_at, b.id), '[]'::jsonb)
  into before_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) < (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
    order by m.created_at desc, m.id desc
    limit least(greatest(coalesce(before_count, 1), 0), 10)
  ) b;

  select coalesce(jsonb_agg(public.search_message_json(a, 0, caller)
    order by a.created_at, a.id), '[]'::jsonb)
  into after_rows
  from (
    select m.*
    from public.messages m
    where m.conversation_id = target.conversation_id
      and (m.created_at, m.id) > (target.created_at, target.id)
      and m.recalled_at is null
      and m.type <> 'system'
    order by m.created_at, m.id
    limit least(greatest(coalesce(after_count, 1), 0), 10)
  ) a;

  return jsonb_build_object('before', before_rows, 'after', after_rows);
end;
$$;

-- The one-argument search (202610130023) reads the search entries.
create or replace function public.search_messages(
  search_query text
)
returns table (
  message_id uuid,
  conversation_id uuid,
  conversation_title text,
  sender_id uuid,
  sender_name text,
  body text,
  type text,
  created_at timestamptz,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  with matches as (
    select
      e.message_id,
      ts_rank(
        e.vector,
        websearch_to_tsquery('simple', public.search_split_cjk(trim(search_query)))
      ) as rank
    from public.message_search_entries e
    where trim(search_query) <> ''
      and e.conversation_id in (
        select public.current_user_readable_conversation_ids()
      )
      and e.vector @@ websearch_to_tsquery(
        'simple',
        public.search_split_cjk(trim(search_query))
      )
    order by rank desc, e.created_at desc
    limit 50
  )
  select
    m.id,
    m.conversation_id,
    coalesce(c.title, peer.display_name) as conversation_title,
    m.sender_id,
    sender.display_name as sender_name,
    m.body,
    m.type,
    m.created_at,
    matches.rank
  from matches
  join public.messages m on m.id = matches.message_id
  join public.conversations c on c.id = m.conversation_id
  join public.profiles sender on sender.id = m.sender_id
  left join public.conversation_members direct_peer_membership
    on direct_peer_membership.conversation_id = c.id
    and direct_peer_membership.user_id <> auth.uid()
    and c.type = 'direct'
  left join public.profiles peer on peer.id = direct_peer_membership.user_id
  order by matches.rank desc, m.created_at desc;
$$;

revoke execute on function public.search_scope_conversation_ids(jsonb) from public;
revoke execute on function public.search_scope_conversation_ids(jsonb) from anon;
revoke execute on function public.search_message_json(public.messages, real, uuid) from public;
revoke execute on function public.search_message_json(public.messages, real, uuid) from anon;
revoke execute on function public.search_message_json(public.messages, real, uuid) from authenticated;
revoke execute on function public.search_conversation_json(uuid, uuid) from public;
revoke execute on function public.search_conversation_json(uuid, uuid) from anon;
revoke execute on function public.search_conversation_json(uuid, uuid) from authenticated;
revoke execute on function public.search_messages(text, jsonb, jsonb, text, integer, jsonb) from public;
revoke execute on function public.search_messages(text, jsonb, jsonb, text, integer, jsonb) from anon;
revoke execute on function public.search_message_context(uuid, integer, integer) from public;
revoke execute on function public.search_message_context(uuid, integer, integer) from anon;

grant execute on function public.search_uuid_array(jsonb) to authenticated;
grant execute on function public.search_filter_instant(text, integer, integer) to authenticated;
grant execute on function public.search_scope_conversation_ids(jsonb) to authenticated;
grant execute on function public.search_messages(text, jsonb, jsonb, text, integer, jsonb) to authenticated;
grant execute on function public.search_message_context(uuid, integer, integer) to authenticated;
grant execute on function public.search_messages(text) to authenticated;
