-- Forms and collection sheets (D1, part 1 of 3): the tables.
--
-- A form is a set of questions that lives in a group or a circle channel (not
-- in a direct chat), as one card in the chat that everybody can fill in. It
-- is the chain (接龙, 202610180060) with more than one line of text: a chain
-- is a form with a single short answer.
--
-- * forms: one row per form. The card in the chat is an ordinary text message
--   whose body is "📝 <title>" (so search, previews and pushes just work) and
--   whose attachment is {kind: 'form', form_id, title}; the chat renders it
--   as the live card. The questions are `fields`, an array of
--   {id, type, label, help, required, options, min, max, integer}; the types
--   are short_text, long_text, number, single_choice, multiple_choice, date,
--   image and member.
-- * `settings` holds the choices of the creator: anonymous, one_per_person,
--   editable, deadline, max_responses and results ('creator' | 'after_submit'
--   | 'everyone': who may read the answers). The functions of part 2 and 3
--   validate and normalise it.
-- * form_responses: one row per answer sheet. Without the one-per-person
--   setting a person may send several. `user_id` is always stored (so that
--   "one per person", editing and reminding work) but a client can only read
--   its OWN rows: nobody else can read the table, and the functions that
--   return responses (get_form_results) leave `user_id` out of an anonymous
--   form, even for its creator.
-- * Nothing is written by clients directly: create_form, submit_form_response,
--   set_form_closed and remind_form_unfilled check membership, whether the
--   person may send there, the deadline, the cap and the answers.
-- * A form follows its card, as a chain does (202610190012): while the card
--   waits for the AI guard, after it is deleted or when it expired, nobody can
--   read the form, its responses or answer it (form_card_visible).
-- * Live updates: every change to a response touches the form's row
--   (response_count, updated_at), and forms is in the supabase_realtime
--   publication, so a card re-reads get_form when it changes.

create table if not exists public.forms (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete set null,
  creator_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  description text not null default '',
  fields jsonb not null,
  settings jsonb not null default '{}'::jsonb,
  response_count integer not null default 0,
  closed_at timestamptz,
  closed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint forms_title_length check (char_length(title) between 1 and 120),
  constraint forms_description_length check (char_length(description) <= 1000),
  constraint forms_fields_is_array check (jsonb_typeof(fields) = 'array'),
  constraint forms_settings_is_object check (jsonb_typeof(settings) = 'object')
);

create index if not exists forms_conversation_idx
  on public.forms (conversation_id, created_at desc);

create table if not exists public.form_responses (
  id uuid primary key default gen_random_uuid(),
  form_id uuid not null references public.forms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  answers jsonb not null,
  -- clock_timestamp, not now(): two answers in one transaction keep their order.
  submitted_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint form_responses_answers_is_object check (jsonb_typeof(answers) = 'object')
);

create index if not exists form_responses_form_idx
  on public.form_responses (form_id, submitted_at, id);
create index if not exists form_responses_user_idx
  on public.form_responses (user_id, form_id);

alter table public.forms enable row level security;
alter table public.form_responses enable row level security;

revoke all on public.forms from anon, authenticated;
revoke all on public.form_responses from anon, authenticated;
grant select on public.forms to authenticated;
grant select on public.form_responses to authenticated;

-- Whether the card message of a form can be read by the caller: it exists, is
-- not deleted or expired, and is not held for review (unless they sent it or
-- moderate). The same rule as chain_card_visible (202610190012), which it asks.
create or replace function public.form_card_visible(card_message_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.chain_card_visible(card_message_id);
$$;

revoke execute on function public.form_card_visible(uuid) from public, anon;
grant execute on function public.form_card_visible(uuid) to authenticated;

drop policy if exists forms_select on public.forms;
create policy forms_select on public.forms
  for select to authenticated
  using (
    public.is_current_user_conversation_member(conversation_id)
    and public.form_card_visible(message_id)
  );

-- A person reads their OWN answers and nobody else's, whatever the form:
-- what the creator and the others see comes from get_form_results.
drop policy if exists form_responses_select_own on public.form_responses;
create policy form_responses_select_own on public.form_responses
  for select to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.forms f
      where f.id = form_responses.form_id
        and public.is_current_user_conversation_member(f.conversation_id)
        and public.form_card_visible(f.message_id)
    )
  );

-- Every change of a response touches the form, which is what Realtime sends.
create or replace function public.form_responses_touch_form()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid := coalesce(new.form_id, old.form_id);
begin
  update public.forms f
  set response_count = (
        select count(*)::integer from public.form_responses r where r.form_id = f.id
      ),
      updated_at = clock_timestamp()
  where f.id = target;
  return null;
end;
$$;

drop trigger if exists form_responses_touch on public.form_responses;
create trigger form_responses_touch
  after insert or update or delete on public.form_responses
  for each row execute function public.form_responses_touch_form();

revoke execute on function public.form_responses_touch_form() from public, anon, authenticated;

-- The deadline in the settings, or null.
create or replace function public.form_deadline(form_row public.forms)
returns timestamptz
language sql
stable
as $$
  select nullif(form_row.settings->>'deadline', '')::timestamptz;
$$;

-- Whether the form no longer takes answers.
create or replace function public.form_is_closed(form_row public.forms)
returns boolean
language sql
stable
as $$
  select form_row.closed_at is not null
    or (
      nullif(form_row.settings->>'deadline', '') is not null
      and (form_row.settings->>'deadline')::timestamptz <= now()
    );
$$;

revoke execute on function public.form_deadline(public.forms) from public, anon;
revoke execute on function public.form_is_closed(public.forms) from public, anon;
grant execute on function public.form_deadline(public.forms) to authenticated;
grant execute on function public.form_is_closed(public.forms) to authenticated;

-- Whether [p_user_id] could read the conversation: a member who may view the
-- channel when it is a circle channel (or a thread of one).
create or replace function public.form_user_can_view(
  p_conversation_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = p_conversation_id
        and cm.user_id = p_user_id
    )
    and public.user_has_conversation_channel_permission(
      p_conversation_id, p_user_id, 'view_channel'
    );
$$;

revoke execute on function public.form_user_can_view(uuid, uuid) from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'forms'
    )
  then
    alter publication supabase_realtime add table public.forms;
  end if;
end;
$$;
