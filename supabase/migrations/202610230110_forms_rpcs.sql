-- Forms and collection sheets (D1, part 2 of 3): make a form, read it, answer
-- it.
--
-- * create_form(conversation, title, description, fields, settings) posts the
--   card. Not for direct chats (and not for the note to self, which is one):
--   groups, circle channels and their threads, the same places as chains. The
--   description and the questions are free text that is no part of the card's
--   body, so the AI guard never sees them: a member the guard would hold
--   (chain_note_needs_review) cannot start a form yet (form_held).
-- * form_normalize_fields / form_normalize_settings turn what the client sent
--   into the stored shape and refuse the rest, so the stored form is always
--   one the other functions can read.
-- * get_form / get_forms read what a card shows, in one go (get_forms is the
--   batch of get_chains: the same objects, nothing for a form the caller
--   cannot see).
-- * submit_form_response(form, answers) is the one way to answer. It checks
--   membership, the right to send, blocking, the deadline and the close, the
--   cap, one answer sheet per person (and editing, when the creator allows
--   it), and every answer: required, type, valid options, valid members, a
--   picture that lives in this conversation's folder and was uploaded by the
--   caller. A failure says which question (the error's detail is the field
--   id). The free text of a member the AI guard would hold is dropped, as the
--   note of a chain line is (text_held = true).
--
-- Picture answers are files of chat-images under <conversation id>/forms/
-- <form id>/, the folder rule of 202610190010: the storage policies already
-- let members of the conversation read and (who may send) upload there.

-- ----------------------------------------------------------------- helpers

create or replace function public.form_normalize_fields(raw jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  item jsonb;
  opt jsonb;
  out_fields jsonb := '[]'::jsonb;
  out_options jsonb;
  built jsonb;
  seen_ids text[] := array[]::text[];
  seen_options text[];
  fid text;
  ftype text;
  flabel text;
  fhelp text;
  oid text;
  olabel text;
  fmin numeric;
  fmax numeric;
begin
  if raw is null
    or jsonb_typeof(raw) <> 'array'
    or jsonb_array_length(raw) not between 1 and 30
    or length(raw::text) > 60000
  then
    raise exception 'form_fields_invalid' using errcode = '22023';
  end if;

  for item in select * from jsonb_array_elements(raw) loop
    if jsonb_typeof(item) <> 'object'
      or jsonb_typeof(item->'id') is distinct from 'string'
      or jsonb_typeof(item->'type') is distinct from 'string'
      or jsonb_typeof(item->'label') is distinct from 'string'
      or coalesce(jsonb_typeof(item->'required'), 'boolean') <> 'boolean'
      or coalesce(jsonb_typeof(item->'help'), 'string') not in ('string', 'null')
    then
      raise exception 'form_fields_invalid' using errcode = '22023';
    end if;

    fid := item->>'id';
    ftype := item->>'type';
    flabel := btrim(item->>'label');
    fhelp := btrim(coalesce(item->>'help', ''));

    if fid !~ '^[a-z0-9_]{1,24}$' or fid = any (seen_ids) then
      raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
    end if;
    seen_ids := seen_ids || fid;

    if ftype not in (
      'short_text', 'long_text', 'number', 'single_choice',
      'multiple_choice', 'date', 'image', 'member'
    ) then
      raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
    end if;
    if char_length(flabel) not between 1 and 200 or char_length(fhelp) > 300 then
      raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
    end if;

    built := jsonb_build_object(
      'id', fid,
      'type', ftype,
      'label', flabel,
      'required', coalesce((item->>'required')::boolean, false)
    );
    if fhelp <> '' then
      built := built || jsonb_build_object('help', fhelp);
    end if;

    if ftype in ('single_choice', 'multiple_choice') then
      if jsonb_typeof(item->'options') is distinct from 'array'
        or jsonb_array_length(item->'options') not between 2 and 30
      then
        raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
      end if;
      out_options := '[]'::jsonb;
      seen_options := array[]::text[];
      for opt in select * from jsonb_array_elements(item->'options') loop
        if jsonb_typeof(opt) <> 'object'
          or jsonb_typeof(opt->'id') is distinct from 'string'
          or jsonb_typeof(opt->'label') is distinct from 'string'
        then
          raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
        end if;
        oid := opt->>'id';
        olabel := btrim(opt->>'label');
        if oid !~ '^[a-z0-9_]{1,24}$'
          or oid = any (seen_options)
          or char_length(olabel) not between 1 and 100
        then
          raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
        end if;
        seen_options := seen_options || oid;
        out_options := out_options || jsonb_build_array(
          jsonb_build_object('id', oid, 'label', olabel)
        );
      end loop;
      built := built || jsonb_build_object('options', out_options);
    elsif ftype = 'number' then
      if coalesce(jsonb_typeof(item->'min'), 'number') not in ('number', 'null')
        or coalesce(jsonb_typeof(item->'max'), 'number') not in ('number', 'null')
        or coalesce(jsonb_typeof(item->'integer'), 'boolean') not in ('boolean', 'null')
      then
        raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
      end if;
      fmin := (item->>'min')::numeric;
      fmax := (item->>'max')::numeric;
      if (fmin is not null and abs(fmin) > 1000000000000)
        or (fmax is not null and abs(fmax) > 1000000000000)
        or (fmin is not null and fmax is not null and fmin > fmax)
      then
        raise exception 'form_fields_invalid' using errcode = '22023', detail = fid;
      end if;
      if fmin is not null then
        built := built || jsonb_build_object('min', fmin);
      end if;
      if fmax is not null then
        built := built || jsonb_build_object('max', fmax);
      end if;
      if coalesce((item->>'integer')::boolean, false) then
        built := built || jsonb_build_object('integer', true);
      end if;
    end if;

    out_fields := out_fields || jsonb_build_array(built);
  end loop;

  return out_fields;
end;
$$;

create or replace function public.form_normalize_settings(raw jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  src jsonb := coalesce(raw, '{}'::jsonb);
  anonymous boolean;
  one_per_person boolean;
  editable boolean;
  results text;
  deadline timestamptz;
  max_responses integer;
  out jsonb;
begin
  if jsonb_typeof(src) <> 'object' then
    raise exception 'form_settings_invalid' using errcode = '22023';
  end if;
  if coalesce(jsonb_typeof(src->'anonymous'), 'boolean') not in ('boolean', 'null')
    or coalesce(jsonb_typeof(src->'one_per_person'), 'boolean') not in ('boolean', 'null')
    or coalesce(jsonb_typeof(src->'editable'), 'boolean') not in ('boolean', 'null')
    or coalesce(jsonb_typeof(src->'results'), 'string') not in ('string', 'null')
    or coalesce(jsonb_typeof(src->'deadline'), 'string') not in ('string', 'null')
    or coalesce(jsonb_typeof(src->'max_responses'), 'number') not in ('number', 'null')
  then
    raise exception 'form_settings_invalid' using errcode = '22023';
  end if;

  anonymous := coalesce((src->>'anonymous')::boolean, false);
  one_per_person := coalesce((src->>'one_per_person')::boolean, true);
  editable := one_per_person and coalesce((src->>'editable')::boolean, true);
  results := coalesce(src->>'results', 'creator');
  if results not in ('creator', 'after_submit', 'everyone') then
    raise exception 'form_settings_invalid' using errcode = '22023';
  end if;

  if nullif(src->>'deadline', '') is not null then
    begin
      deadline := (src->>'deadline')::timestamptz;
    exception when others then
      raise exception 'form_deadline_invalid' using errcode = '22023';
    end;
    if deadline <= now() or deadline > now() + interval '366 days' then
      raise exception 'form_deadline_invalid' using errcode = '22023';
    end if;
  end if;

  if src->'max_responses' is not null and jsonb_typeof(src->'max_responses') = 'number' then
    if (src->>'max_responses')::numeric <> trunc((src->>'max_responses')::numeric)
      or (src->>'max_responses')::numeric not between 1 and 500
    then
      raise exception 'form_max_invalid' using errcode = '22023';
    end if;
    max_responses := (src->>'max_responses')::integer;
  end if;

  out := jsonb_build_object(
    'anonymous', anonymous,
    'one_per_person', one_per_person,
    'editable', editable,
    'results', results
  );
  if deadline is not null then
    out := out || jsonb_build_object(
      'deadline',
      to_char(deadline at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    );
  end if;
  if max_responses is not null then
    out := out || jsonb_build_object('max_responses', max_responses);
  end if;
  return out;
end;
$$;

-- The answers of one sheet, checked against the form's questions. Returns the
-- cleaned answers (only questions that were answered, trimmed); raises
-- form_answer_required / form_answer_invalid / form_unknown_field with the
-- question's id as the detail.
create or replace function public.form_clean_answers(
  f public.forms,
  answers jsonb,
  uid uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  field jsonb;
  answer_key text;
  fid text;
  ftype text;
  val jsonb;
  kind text;
  txt text;
  limit_chars integer;
  num numeric;
  picked jsonb;
  item jsonb;
  seen text[];
  path text;
  cleaned jsonb := '{}'::jsonb;
begin
  if answers is null or jsonb_typeof(answers) <> 'object' then
    raise exception 'form_answer_invalid' using errcode = '22023';
  end if;

  for answer_key in select jsonb_object_keys(answers) loop
    if not exists (
      select 1 from jsonb_array_elements(f.fields) e where e->>'id' = answer_key
    ) then
      raise exception 'form_unknown_field' using errcode = '22023', detail = answer_key;
    end if;
  end loop;

  for field in select * from jsonb_array_elements(f.fields) loop
    fid := field->>'id';
    ftype := field->>'type';
    val := answers->fid;
    kind := coalesce(jsonb_typeof(val), 'null');

    if kind = 'null'
      or (kind = 'string' and btrim(val #>> '{}') = '')
      or (kind = 'array' and jsonb_array_length(val) = 0)
    then
      if coalesce((field->>'required')::boolean, false) then
        raise exception 'form_answer_required' using errcode = '22023', detail = fid;
      end if;
      continue;
    end if;

    if ftype in ('short_text', 'long_text') then
      txt := btrim(val #>> '{}');
      limit_chars := 2000;
      if ftype = 'short_text' then
        limit_chars := 200;
      end if;
      if kind <> 'string' or char_length(txt) > limit_chars then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      cleaned := cleaned || jsonb_build_object(fid, txt);

    elsif ftype = 'number' then
      if kind <> 'number' then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      num := (val #>> '{}')::numeric;
      if abs(num) > 1000000000000
        or (coalesce((field->>'integer')::boolean, false) and num <> trunc(num))
        or (field->>'min' is not null and num < (field->>'min')::numeric)
        or (field->>'max' is not null and num > (field->>'max')::numeric)
      then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      cleaned := cleaned || jsonb_build_object(fid, num);

    elsif ftype = 'single_choice' then
      txt := val #>> '{}';
      if kind <> 'string' or not exists (
        select 1 from jsonb_array_elements(field->'options') o where o->>'id' = txt
      ) then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      cleaned := cleaned || jsonb_build_object(fid, txt);

    elsif ftype = 'multiple_choice' then
      if kind <> 'array' then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      seen := array[]::text[];
      picked := '[]'::jsonb;
      for item in select * from jsonb_array_elements(val) loop
        txt := item #>> '{}';
        if jsonb_typeof(item) <> 'string'
          or txt = any (seen)
          or not exists (
            select 1 from jsonb_array_elements(field->'options') o where o->>'id' = txt
          )
        then
          raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
        end if;
        seen := seen || txt;
        picked := picked || to_jsonb(txt);
      end loop;
      cleaned := cleaned || jsonb_build_object(fid, picked);

    elsif ftype = 'date' then
      txt := val #>> '{}';
      if kind <> 'string' or txt !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      begin
        if to_char(txt::date, 'YYYY-MM-DD') <> txt then
          raise exception 'form_answer_invalid';
        end if;
      exception when others then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end;
      cleaned := cleaned || jsonb_build_object(fid, txt);

    elsif ftype = 'image' then
      -- A file of this conversation's folder for this form, uploaded by the
      -- caller (nobody else's file, nothing outside the chat's folder).
      path := val #>> '{path}';
      if kind <> 'object'
        or val #>> '{bucket}' is distinct from 'chat-images'
        or path is null
        or path !~ ('^' || f.conversation_id::text || '/forms/' || f.id::text || '/[A-Za-z0-9._-]{1,120}$')
        or not exists (
          select 1
          from storage.objects o
          where o.bucket_id = 'chat-images'
            and o.name = path
            and (o.owner = uid or o.owner_id = uid::text)
        )
      then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      picked := jsonb_build_object('bucket', 'chat-images', 'path', path);
      if jsonb_typeof(val->'mime_type') = 'string' and char_length(val->>'mime_type') <= 100 then
        picked := picked || jsonb_build_object('mime_type', val->>'mime_type');
      end if;
      cleaned := cleaned || jsonb_build_object(fid, picked);

    elsif ftype = 'member' then
      txt := val #>> '{}';
      if kind <> 'string'
        or txt !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or not exists (
          select 1
          from public.conversation_members cm
          where cm.conversation_id = f.conversation_id
            and cm.user_id = txt::uuid
        )
      then
        raise exception 'form_answer_invalid' using errcode = '22023', detail = fid;
      end if;
      cleaned := cleaned || jsonb_build_object(fid, lower(txt));
    end if;
  end loop;

  return cleaned;
end;
$$;

revoke execute on function public.form_normalize_fields(jsonb) from public, anon, authenticated;
revoke execute on function public.form_normalize_settings(jsonb) from public, anon, authenticated;
revoke execute on function public.form_clean_answers(public.forms, jsonb, uuid) from public, anon, authenticated;

-- ------------------------------------------------------------- create_form

-- Posts a form and its card into [target_conversation_id].
-- Answers {form_id, message_id}.
create or replace function public.create_form(
  target_conversation_id uuid,
  form_title text,
  form_description text default null,
  form_fields jsonb default null,
  form_settings jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  clean_title text := btrim(coalesce(form_title, ''));
  clean_description text := btrim(coalesce(form_description, ''));
  fields_clean jsonb;
  settings_clean jsonb;
  new_form_id uuid := gen_random_uuid();
  new_message_id uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;
  -- Groups, circle channels and their threads; not direct chats, which also
  -- rules out the note to self.
  if not public.chain_conversation_allowed(target_conversation_id) then
    raise exception 'form_not_allowed' using errcode = '22023';
  end if;
  if not public.can_current_user_send_in_conversation(target_conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if char_length(clean_title) not between 1 and 120 then
    raise exception 'form_title_invalid' using errcode = '22023';
  end if;
  if char_length(clean_description) > 1000 then
    raise exception 'form_text_too_long' using errcode = '22023';
  end if;

  fields_clean := public.form_normalize_fields(form_fields);
  settings_clean := public.form_normalize_settings(form_settings);

  -- The questions are no part of the card's text, which is what the AI guard
  -- reads: a member it would hold does not start forms yet.
  if public.chain_note_needs_review(target_conversation_id, uid) then
    raise exception 'form_held' using errcode = '42501';
  end if;

  insert into public.forms (
    id, conversation_id, creator_id, title, description, fields, settings
  )
  values (
    new_form_id, target_conversation_id, uid, clean_title, clean_description,
    fields_clean, settings_clean
  );

  insert into public.messages (conversation_id, sender_id, type, body, attachment)
  values (
    target_conversation_id,
    uid,
    'text',
    E'\U0001F4DD ' || clean_title,
    jsonb_build_object('kind', 'form', 'form_id', new_form_id, 'title', clean_title)
  )
  returning id into new_message_id;

  update public.forms set message_id = new_message_id where id = new_form_id;

  return jsonb_build_object('form_id', new_form_id, 'message_id', new_message_id);
end;
$$;

-- ----------------------------------------------------------------- reading

-- Whether the caller may read the answers of [f].
create or replace function public.form_can_view_results(f public.forms)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and (
      f.creator_id = auth.uid()
      or coalesce(f.settings->>'results', 'creator') = 'everyone'
      or (
        coalesce(f.settings->>'results', 'creator') = 'after_submit'
        and exists (
          select 1
          from public.form_responses r
          where r.form_id = f.id and r.user_id = auth.uid()
        )
      )
    );
$$;

revoke execute on function public.form_can_view_results(public.forms) from public, anon, authenticated;

-- Everything a card or the fill-in page shows, in one read.
create or replace function public.get_form(target_form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  f public.forms%rowtype;
  channel_circle_id uuid;
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into f from public.forms where id = target_form_id;
  if f.id is null
    or not public.is_current_user_conversation_member(f.conversation_id)
    or not public.form_card_visible(f.message_id)
  then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;

  select cc.circle_id into channel_circle_id
  from public.circle_channels cc
  where cc.id = public.conversation_circle_channel_id(f.conversation_id);

  select jsonb_build_object(
    'id', f.id,
    'conversation_id', f.conversation_id,
    'message_id', f.message_id,
    'title', f.title,
    'description', f.description,
    'fields', f.fields,
    'settings', f.settings,
    'response_count', f.response_count,
    'closed', public.form_is_closed(f),
    'closed_at', f.closed_at,
    'created_by', f.creator_id,
    'created_at', f.created_at,
    'creator_name', coalesce(
      nullif(btrim(creator_member.nickname), ''),
      nullif(btrim(creator.display_name), ''),
      creator.username
    ),
    'can_manage', f.creator_id = auth.uid(),
    'can_view_results', public.form_can_view_results(f),
    'my_response', (
      select jsonb_build_object(
        'id', r.id,
        'answers', r.answers,
        'submitted_at', r.submitted_at,
        'updated_at', r.updated_at
      )
      from public.form_responses r
      where r.form_id = f.id and r.user_id = auth.uid()
      order by r.submitted_at desc, r.id
      limit 1
    ),
    'my_response_count', (
      select count(*)::integer
      from public.form_responses r
      where r.form_id = f.id and r.user_id = auth.uid()
    )
  )
  into result
  from public.profiles creator
  left join public.circle_members creator_member
    on creator_member.circle_id = channel_circle_id
    and creator_member.user_id = creator.id
  where creator.id = f.creator_id;

  return result;
end;
$$;

-- get_form for several forms at once (a chat with many cards): the same
-- objects, in no particular order, and nothing for a form the caller cannot
-- see. It asks get_form, so the rules of who reads a form stay in one place.
create or replace function public.get_forms(target_form_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  one_id uuid;
  one jsonb;
  result jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if coalesce(cardinality(target_form_ids), 0) > 50 then
    raise exception 'Too many forms' using errcode = '22023';
  end if;

  for one_id in
    select distinct ids.id
    from unnest(target_form_ids) as ids(id)
    where ids.id is not null
  loop
    begin
      one := public.get_form(one_id);
      if one is not null then
        result := result || jsonb_build_array(one);
      end if;
    exception when sqlstate 'P0002' then
      null;
    end;
  end loop;

  return result;
end;
$$;

-- ------------------------------------------------------ submit_form_response

-- Sends (or, when the creator allows it, changes) the caller's answers.
-- Answers {response_id, updated, text_held}.
create or replace function public.submit_form_response(
  target_form_id uuid,
  response_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  f public.forms%rowtype;
  one_per_person boolean;
  editable boolean;
  max_responses integer;
  existing public.form_responses%rowtype;
  cleaned jsonb;
  held boolean := false;
  field jsonb;
  saved_id uuid;
  was_updated boolean := false;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into f from public.forms where id = target_form_id for update;
  if f.id is null
    or not public.is_current_user_conversation_member(f.conversation_id)
    or not public.form_card_visible(f.message_id)
  then
    raise exception 'Form not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_send_in_conversation(f.conversation_id) then
    raise exception 'You cannot send messages here' using errcode = '42501';
  end if;
  if public.is_current_user_blocked_in_conversation(f.conversation_id) then
    raise exception 'Cannot send messages in this conversation' using errcode = '42501';
  end if;
  if public.form_is_closed(f) then
    raise exception 'form_closed' using errcode = 'P0001';
  end if;

  one_per_person := coalesce((f.settings->>'one_per_person')::boolean, true);
  editable := one_per_person and coalesce((f.settings->>'editable')::boolean, true);
  max_responses := nullif(f.settings->>'max_responses', '')::integer;

  if one_per_person then
    select * into existing
    from public.form_responses r
    where r.form_id = f.id and r.user_id = uid
    order by r.submitted_at, r.id
    limit 1;
    if existing.id is not null and not editable then
      raise exception 'form_already_submitted' using errcode = '23505';
    end if;
  end if;

  if existing.id is null
    and max_responses is not null
    and f.response_count >= max_responses
  then
    raise exception 'form_full' using errcode = 'P0001';
  end if;

  cleaned := public.form_clean_answers(f, response_answers, uid);

  -- Free text of a member the AI guard would hold is not let through.
  if public.chain_note_needs_review(f.conversation_id, uid) then
    for field in select * from jsonb_array_elements(f.fields) loop
      if field->>'type' in ('short_text', 'long_text') and cleaned ? (field->>'id') then
        cleaned := cleaned - (field->>'id');
        held := true;
      end if;
    end loop;
  end if;

  if existing.id is not null then
    update public.form_responses
    set answers = cleaned, updated_at = clock_timestamp()
    where id = existing.id
    returning id into saved_id;
    was_updated := true;
  else
    insert into public.form_responses (form_id, user_id, answers)
    values (f.id, uid, cleaned)
    returning id into saved_id;
  end if;

  return jsonb_build_object(
    'response_id', saved_id,
    'updated', was_updated,
    'text_held', held
  );
end;
$$;

revoke execute on function public.create_form(uuid, text, text, jsonb, jsonb) from public, anon;
revoke execute on function public.get_form(uuid) from public, anon;
revoke execute on function public.get_forms(uuid[]) from public, anon;
revoke execute on function public.submit_form_response(uuid, jsonb) from public, anon;

grant execute on function public.create_form(uuid, text, text, jsonb, jsonb) to authenticated;
grant execute on function public.get_form(uuid) to authenticated;
grant execute on function public.get_forms(uuid[]) to authenticated;
grant execute on function public.submit_form_response(uuid, jsonb) to authenticated;
