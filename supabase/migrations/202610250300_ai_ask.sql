-- Ask AI about your chats (roadmap F1, stage 1: no vectors): what the `ai`
-- function's `ask` action may read. Every function here is for the service
-- role only; the function calls them with the id of the person who asked,
-- which it took from their verified token.
--
-- The model never searches by itself. The `ai` function turns the question
-- into two or three groups of keywords, ai_ask_search finds messages with the
-- full-text index that message search uses (message_search_entries), and the
-- model answers from those messages alone.
--
-- What may be read (the same rules as the assistant's context 202610230420 and
-- the daily digest's ai_digest_messages 202610230520, and no looser):
--   * only conversations the asker can read right now
--     (current_user_readable_conversation_ids, taken as THEM by setting the
--     transaction's JWT claims, the way the other AI functions do), narrowed
--     to the scope they chose (one conversation with its threads, one circle,
--     or everywhere), and never one where the circle or the group's owner
--     turned AI off (conversation_ai_assistant_allowed);
--   * nothing at all when the asker turned AI off (user_ai_settings);
--   * never recalled or expired messages, never messages waiting for or
--     removed by the AI guard or an edit review (review_state), never
--     view-once pictures, never notices, never the assistant's own replies,
--     never a sender the asker blocked or who blocked them.
--   The asker's own messages are included: they can see them.
--
-- ai_ask_visible re-checks a list of message ids with the same rules. The
-- function uses it after the model answered, so a message recalled while the
-- model was thinking is not quoted as a source.

-- The conversations an ask may look in: readable by the asker, inside the
-- scope, and with AI allowed. Sets the claims to the asker.
create or replace function public.ai_ask_conversations(
  p_user_id uuid,
  p_scope jsonb
)
returns uuid[]
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  scoped uuid[];
begin
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', p_user_id, 'role', 'authenticated')::text,
    true
  );

  scoped := public.search_scope_conversation_ids(coalesce(p_scope, '{"type":"everywhere"}'::jsonb));
  return coalesce((
    select array_agg(s.id)
    from unnest(scoped) s(id)
    where public.conversation_ai_assistant_allowed(s.id)
  ), '{}'::uuid[]);
end;
$$;

-- Whether the asker may ask here at all, before anything is searched or any
-- model is called:
--   ok         go ahead ("conversations" is how many may be searched)
--   user_off   the asker turned AI off in Settings
--   ai_off     the scope exists but every conversation in it has AI off
--   not_found  the scope is not one the asker can read, or is malformed
create or replace function public.ai_ask_scope(
  p_user_id uuid,
  p_scope jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  kind text := coalesce(p_scope->>'type', 'everywhere');
  readable uuid[];
  allowed uuid[];
begin
  if exists (
    select 1
    from public.user_ai_settings s
    where s.user_id = p_user_id and s.ai_enabled = false
  ) then
    return jsonb_build_object('status', 'user_off', 'conversations', 0);
  end if;
  if kind not in ('everywhere', 'circle', 'conversation') then
    return jsonb_build_object('status', 'not_found', 'conversations', 0);
  end if;

  begin
    perform set_config('request.jwt.claim.sub', p_user_id::text, true);
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object('sub', p_user_id, 'role', 'authenticated')::text,
      true
    );
    readable := public.search_scope_conversation_ids(p_scope);
  exception when others then
    return jsonb_build_object('status', 'not_found', 'conversations', 0);
  end;
  if kind <> 'everywhere' and cardinality(readable) = 0 then
    return jsonb_build_object('status', 'not_found', 'conversations', 0);
  end if;

  allowed := public.ai_ask_conversations(p_user_id, p_scope);
  if kind <> 'everywhere' and cardinality(allowed) = 0 then
    return jsonb_build_object('status', 'ai_off', 'conversations', 0);
  end if;
  return jsonb_build_object('status', 'ok', 'conversations', cardinality(allowed));
end;
$$;

-- The messages that match [p_groups], best first. A group is a few words;
-- a message matches a group when it has every word of it, and a message
-- matches the search when it matches any group. Words match through the
-- full-text vector (whole words, and any run of Chinese, Japanese or Korean
-- characters) or, from three characters, as part of a word through the
-- trigram index - the same two ways message search matches. At most 3 groups
-- of 6 words of 64 characters are read; the rest is ignored.
-- Order: messages that match more groups first, then the closer full-text
-- match, then the newer.
create or replace function public.ai_ask_search(
  p_user_id uuid,
  p_groups text[],
  p_scope jsonb,
  p_limit integer default 50
)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  type text,
  body text,
  attachment_name text,
  webhook_name text,
  created_at timestamptz,
  score real,
  place jsonb
)
language plpgsql
volatile
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  ids uuid[];
  group_text text;
  words text[];
  word text;
  word_query tsquery;
  word_sql text;
  group_sql text;
  any_sql text := '';
  score_sql text := '0';
  rank_query tsquery;
  group_count integer := 0;
  page_size integer := least(greatest(coalesce(p_limit, 50), 1), 50);
begin
  if exists (
    select 1
    from public.user_ai_settings s
    where s.user_id = p_user_id and s.ai_enabled = false
  ) then
    return;
  end if;
  ids := public.ai_ask_conversations(p_user_id, p_scope);
  if cardinality(ids) = 0 then
    return;
  end if;

  foreach group_text in array coalesce(p_groups, '{}'::text[]) loop
    exit when group_count >= 3;
    words := array(
      select left(w, 64)
      from regexp_split_to_table(lower(btrim(coalesce(group_text, ''))), '\s+') w
      where w <> ''
      limit 6
    );
    group_sql := '';
    foreach word in array words loop
      word_query := phraseto_tsquery('simple'::regconfig, public.search_split_cjk(word));
      word_sql := null;
      if numnode(word_query) > 0 then
        word_sql := format('e.vector @@ %L::tsquery', word_query::text);
        rank_query := case
          when rank_query is null then word_query
          else rank_query || word_query
        end;
      end if;
      if char_length(word) >= 3 then
        word_sql := concat_ws(
          ' or ',
          word_sql,
          format('e.document like %L', public.search_like_pattern(word))
        );
      end if;
      continue when word_sql is null;
      group_sql := case
        when group_sql = '' then format('(%s)', word_sql)
        else format('%s and (%s)', group_sql, word_sql)
      end;
    end loop;
    continue when group_sql = '';
    group_count := group_count + 1;
    any_sql := case
      when any_sql = '' then format('(%s)', group_sql)
      else format('%s or (%s)', any_sql, group_sql)
    end;
    score_sql := format('%s + (case when %s then 1 else 0 end)', score_sql, group_sql);
  end loop;
  if any_sql = '' then
    return;
  end if;

  return query execute format(
    'select m.id, m.conversation_id, m.sender_id,'
    ' coalesce(nullif(btrim(coalesce(m.webhook_name, '''')), ''''),'
    '   nullif(btrim(coalesce(ca.alias, '''')), ''''),'
    '   nullif(btrim(p.display_name), ''''), p.username, ''Someone''),'
    ' m.type, coalesce(m.body, ''''), m.attachment->>''name'', m.webhook_name,'
    ' m.created_at,'
    ' ((%s) * 10 + %s)::real as score,'
    ' public.search_conversation_json(m.conversation_id, $2) as place'
    ' from public.message_search_entries e'
    ' join public.messages m on m.id = e.message_id'
    ' left join public.profiles p on p.id = m.sender_id'
    ' left join public.contact_aliases ca'
    '   on ca.owner_id = $2 and ca.friend_id = m.sender_id'
    ' where e.conversation_id = any($1)'
    '   and (%s)'
    '   and m.recalled_at is null'
    '   and m.review_state is null'
    '   and (m.expires_at is null or m.expires_at > now())'
    '   and coalesce(m.attachment->>''view_once'', '''') <> ''true'''
    '   and m.type <> ''system'''
    '   and m.ai_reply is null'
    '   and not public.are_users_blocked(m.sender_id, $2)'
    ' order by score desc, m.created_at desc, m.id desc'
    ' limit %s',
    score_sql,
    case
      when rank_query is null then '0'
      else format('ts_rank_cd(e.vector, %L::tsquery)', rank_query::text)
    end,
    any_sql,
    page_size
  ) using ids, p_user_id;
end;
$$;

-- Of [p_message_ids], the ones the asker may still be quoted: the same rules
-- as ai_ask_search, applied to the messages themselves.
create or replace function public.ai_ask_visible(
  p_user_id uuid,
  p_message_ids uuid[]
)
returns uuid[]
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  allowed uuid[];
begin
  if p_message_ids is null or cardinality(p_message_ids) = 0 then
    return '{}'::uuid[];
  end if;
  if exists (
    select 1
    from public.user_ai_settings s
    where s.user_id = p_user_id and s.ai_enabled = false
  ) then
    return '{}'::uuid[];
  end if;
  allowed := public.ai_ask_conversations(p_user_id, '{"type":"everywhere"}'::jsonb);

  return coalesce((
    select array_agg(m.id)
    from public.messages m
    where m.id = any(p_message_ids)
      and m.conversation_id = any(allowed)
      and m.recalled_at is null
      and m.review_state is null
      and (m.expires_at is null or m.expires_at > now())
      and coalesce(m.attachment->>'view_once', '') <> 'true'
      and m.type <> 'system'
      and m.ai_reply is null
      and not public.are_users_blocked(m.sender_id, p_user_id)
  ), '{}'::uuid[]);
end;
$$;

revoke execute on function public.ai_ask_conversations(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.ai_ask_scope(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.ai_ask_search(uuid, text[], jsonb, integer)
  from public, anon, authenticated;
revoke execute on function public.ai_ask_visible(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.ai_ask_conversations(uuid, jsonb) to service_role;
grant execute on function public.ai_ask_scope(uuid, jsonb) to service_role;
grant execute on function public.ai_ask_search(uuid, text[], jsonb, integer) to service_role;
grant execute on function public.ai_ask_visible(uuid, uuid[]) to service_role;
