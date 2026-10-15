-- Member onboarding: a circle can list rules that new members accept
-- before they take part, and a welcome message shown once they have.
--
-- * circle_onboarding (one row per circle): enabled, rules (up to 20 of
--   up to 300 characters) and welcome_message (up to 2000). Members read
--   it with get_circle_onboarding; members with manage_circle change it
--   with set_circle_onboarding (audited as onboarding_update).
-- * circle_members.rules_accepted_at: set by accept_circle_rules. Turning
--   onboarding on counts everyone already in the circle as having
--   accepted, so only members who join afterwards are asked.
-- * While onboarding is on, a member who has not accepted (other than the
--   owner and members with manage_circle) cannot send messages, react,
--   vote in polls or join voice in the circle. Triggers refuse those
--   inserts with SQLSTATE 42501 and detail 'rules_not_accepted'. The
--   messages trigger, messages_check_rules_accepted, runs after
--   messages_check_channel_send and before messages_circle_automod
--   (triggers fire in name order).

alter table public.circle_members
  add column if not exists rules_accepted_at timestamptz;

create table if not exists public.circle_onboarding (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  enabled boolean not null default false,
  rules text[] not null default '{}',
  welcome_message text,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint circle_onboarding_rules_count check (cardinality(rules) <= 20),
  constraint circle_onboarding_welcome_length check (
    welcome_message is null or char_length(welcome_message) between 1 and 2000
  ),
  constraint circle_onboarding_enabled_has_rules check (
    not enabled or cardinality(rules) > 0
  )
);

alter table public.circle_onboarding enable row level security;

revoke insert, update, delete, truncate on public.circle_onboarding from anon, authenticated;

drop policy if exists circle_onboarding_select_member on public.circle_onboarding;
create policy circle_onboarding_select_member
  on public.circle_onboarding for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

-- Whether target_user_id still has to accept target_circle_id's rules.
create or replace function public.circle_member_needs_rules(
  target_circle_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_onboarding o
    join public.circle_members cm
      on cm.circle_id = o.circle_id
      and cm.user_id = target_user_id
    where o.circle_id = target_circle_id
      and o.enabled
      and cm.rules_accepted_at is null
  )
  and not public.circle_member_has_permission(
    target_circle_id,
    target_user_id,
    'manage_circle'
  );
$$;

revoke execute on function public.circle_member_needs_rules(uuid, uuid) from public, anon, authenticated;

-- BEFORE INSERT on messages.
create or replace function public.reject_unaccepted_rules_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type = 'system'
    or new.webhook_id is not null
    or new.webhook_name is not null
  then
    return new;
  end if;

  if exists (
    select 1
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(new.conversation_id)
      and public.circle_member_needs_rules(cc.circle_id, new.sender_id)
  ) then
    raise exception 'Accept the circle rules before taking part'
      using errcode = '42501', detail = 'rules_not_accepted';
  end if;

  return new;
end;
$$;

-- BEFORE INSERT on message_reactions and message_poll_votes.
create or replace function public.reject_unaccepted_rules_action()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circle_channels cc
    where cc.id = public.conversation_circle_channel_id(new.conversation_id)
      and public.circle_member_needs_rules(cc.circle_id, new.user_id)
  ) then
    raise exception 'Accept the circle rules before taking part'
      using errcode = '42501', detail = 'rules_not_accepted';
  end if;
  return new;
end;
$$;

-- BEFORE INSERT on voice_states.
create or replace function public.reject_unaccepted_rules_voice()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.circle_member_needs_rules(new.circle_id, new.user_id) then
    raise exception 'Accept the circle rules before taking part'
      using errcode = '42501', detail = 'rules_not_accepted';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_unaccepted_rules_message() from public, anon, authenticated;
revoke execute on function public.reject_unaccepted_rules_action() from public, anon, authenticated;
revoke execute on function public.reject_unaccepted_rules_voice() from public, anon, authenticated;

drop trigger if exists messages_check_rules_accepted on public.messages;
create trigger messages_check_rules_accepted
  before insert on public.messages
  for each row execute function public.reject_unaccepted_rules_message();

drop trigger if exists message_reactions_check_rules_accepted on public.message_reactions;
create trigger message_reactions_check_rules_accepted
  before insert on public.message_reactions
  for each row execute function public.reject_unaccepted_rules_action();

drop trigger if exists message_poll_votes_check_rules_accepted on public.message_poll_votes;
create trigger message_poll_votes_check_rules_accepted
  before insert on public.message_poll_votes
  for each row execute function public.reject_unaccepted_rules_action();

drop trigger if exists voice_states_check_rules_accepted on public.voice_states;
create trigger voice_states_check_rules_accepted
  before insert on public.voice_states
  for each row execute function public.reject_unaccepted_rules_voice();

-- The circle's onboarding for a member: {enabled, rules, welcome_message,
-- needs_acceptance, accepted_at}.
create or replace function public.get_circle_onboarding(target_circle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  onboarding public.circle_onboarding%rowtype;
  member public.circle_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cm.*
  into member
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = auth.uid();

  if member.user_id is null then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  select o.*
  into onboarding
  from public.circle_onboarding o
  where o.circle_id = target_circle_id;

  return jsonb_build_object(
    'enabled', coalesce(onboarding.enabled, false),
    'rules', to_jsonb(coalesce(onboarding.rules, '{}'::text[])),
    'welcome_message', onboarding.welcome_message,
    'needs_acceptance', public.circle_member_needs_rules(
      target_circle_id,
      auth.uid()
    ),
    'accepted_at', member.rules_accepted_at
  );
end;
$$;

-- Saves the circle's onboarding. Turning it on counts every current
-- member as having accepted.
create or replace function public.set_circle_onboarding(
  target_circle_id uuid,
  is_enabled boolean,
  rule_list text[],
  welcome text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  previous public.circle_onboarding%rowtype;
  cleaned_rules text[];
  cleaned_welcome text := nullif(btrim(coalesce(welcome, '')), '');
  changes jsonb := '{}'::jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_circle'
  ) then
    raise exception 'Only members who can manage the circle can change onboarding'
      using errcode = '42501';
  end if;

  select coalesce(array_agg(btrim(r) order by ordinality), '{}')
  into cleaned_rules
  from unnest(coalesce(rule_list, '{}'::text[])) with ordinality as rules(r, ordinality)
  where btrim(r) <> '';

  if cardinality(cleaned_rules) > 20 then
    raise exception 'Up to 20 rules' using errcode = '22023';
  end if;

  if exists (select 1 from unnest(cleaned_rules) r where char_length(r) > 300) then
    raise exception 'Rules are up to 300 characters' using errcode = '22023';
  end if;

  if cleaned_welcome is not null and char_length(cleaned_welcome) > 2000 then
    raise exception 'The welcome message is up to 2000 characters'
      using errcode = '22023';
  end if;

  if coalesce(is_enabled, false) and cardinality(cleaned_rules) = 0 then
    raise exception 'Add at least one rule before turning onboarding on'
      using errcode = '22023';
  end if;

  select o.*
  into previous
  from public.circle_onboarding o
  where o.circle_id = target_circle_id
  for update;

  insert into public.circle_onboarding (
    circle_id,
    enabled,
    rules,
    welcome_message,
    updated_by,
    updated_at
  )
  values (
    target_circle_id,
    coalesce(is_enabled, false),
    cleaned_rules,
    cleaned_welcome,
    current_user_id,
    now()
  )
  on conflict (circle_id) do update
  set
    enabled = excluded.enabled,
    rules = excluded.rules,
    welcome_message = excluded.welcome_message,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  if coalesce(is_enabled, false) and not coalesce(previous.enabled, false) then
    update public.circle_members cm
    set rules_accepted_at = now()
    where cm.circle_id = target_circle_id
      and cm.rules_accepted_at is null;
  end if;

  if coalesce(previous.enabled, false) is distinct from coalesce(is_enabled, false) then
    changes := changes || jsonb_build_object(
      'enabled',
      jsonb_build_object(
        'old', coalesce(previous.enabled, false),
        'new', coalesce(is_enabled, false)
      )
    );
  end if;
  if coalesce(previous.rules, '{}'::text[]) is distinct from cleaned_rules then
    changes := changes || jsonb_build_object(
      'rule_count',
      jsonb_build_object(
        'old', cardinality(coalesce(previous.rules, '{}'::text[])),
        'new', cardinality(cleaned_rules)
      )
    );
  end if;
  if previous.welcome_message is distinct from cleaned_welcome then
    changes := changes || jsonb_build_object('welcome_message_changed', true);
  end if;

  if changes <> '{}'::jsonb then
    perform public.write_circle_audit(
      target_circle_id,
      'onboarding_update',
      'circle',
      target_circle_id,
      (select c.name from public.circles c where c.id = target_circle_id),
      changes
    );
  end if;
end;
$$;

-- The caller accepts the circle's rules; returns the welcome message.
create or replace function public.accept_circle_rules(target_circle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  welcome text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.circle_members cm
  set rules_accepted_at = coalesce(cm.rules_accepted_at, now())
  where cm.circle_id = target_circle_id
    and cm.user_id = auth.uid();

  if not found then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  select o.welcome_message
  into welcome
  from public.circle_onboarding o
  where o.circle_id = target_circle_id;

  return jsonb_build_object('welcome_message', welcome);
end;
$$;

revoke execute on function public.get_circle_onboarding(uuid) from public, anon;
revoke execute on function public.set_circle_onboarding(uuid, boolean, text[], text) from public, anon;
revoke execute on function public.accept_circle_rules(uuid) from public, anon;
grant execute on function public.get_circle_onboarding(uuid) to authenticated;
grant execute on function public.set_circle_onboarding(uuid, boolean, text[], text) to authenticated;
grant execute on function public.accept_circle_rules(uuid) to authenticated;
