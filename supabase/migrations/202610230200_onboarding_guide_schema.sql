-- Onboarding 2.0 (C2), part 1 of 3: the tables, and the rule that a role
-- anyone can pick for themselves carries no management power.
--
-- A circle can ask new members what they are interested in (prompts with
-- options), give each option roles to hand out and channels to point at,
-- and list tasks for newcomers (read the rules, visit a channel, say
-- something, set an avatar). Part 2 (202610230210) holds the RPCs, part 3
-- (202610230220) the greeting card for new members.
--
-- Tables (all closed to clients: the RPCs read and write them as the
-- table owner and check the caller themselves)
--   circle_onboarding_prompts          the questions: title, required,
--                                      single or multiple choice
--   circle_onboarding_options          the answers to pick from
--   circle_onboarding_option_roles     roles an option gives
--   circle_onboarding_option_channels  channels an option points at
--   circle_guide_tasks                 the newcomer task list
--   circle_guide_settings              the greeting for new members
--   circle_member_onboarding           whether a member has answered, and
--                                      whether they put the guide away
--   circle_member_onboarding_answers   the options a member picked
--   circle_member_guide_tasks          tasks a member has ticked off (only
--                                      ones nothing else can prove, such as
--                                      "visit a channel")
-- Every member row goes with the member (foreign key to circle_members).
--
-- The role rule (what "no management permission" means)
--   A role can be given by an answer only when
--     1. it is a real role of the circle, not @everyone;
--     2. its permissions are a subset of onboarding_safe_permissions():
--        view_channel, send_messages, create_invites and connect_voice (what
--        @everyone has in a new circle). Everything else is management,
--        including mention_everyone: any other bit makes the role refuse.
--     3. it does not outrank a role that holds management permissions
--        (position below the lowest such role), so that taking an
--        interest role never puts someone out of reach of ranked moderation.
--   onboarding_role_problem() answers all three. It is asked when a role is
--   attached to an option (a trigger, whatever the writer), and again every
--   time someone answers (so a role that was edited into a powerful one
--   later is never handed out). A trigger on circle_roles also unlinks the
--   role and takes it back from the people who picked it for themselves
--   (circle_member_roles.via_onboarding) the moment it gains such a
--   permission; roles an admin gave by hand stay.

-- A role given by an answer is told apart from one given by hand.
alter table public.circle_member_roles
  add column if not exists via_onboarding boolean not null default false;

-- ---------------------------------------------------------------------------
-- The role rule
-- ---------------------------------------------------------------------------

create or replace function public.onboarding_safe_permissions()
returns bigint
language sql
immutable
set search_path = public
as $$
  select public.circle_permission_bits(array[
    'view_channel',
    'send_messages',
    'create_invites',
    'connect_voice'
  ]);
$$;

-- Why a role cannot be handed out by an answer: 'missing', 'default',
-- 'permissions' or 'rank'; null when it can.
create or replace function public.onboarding_role_problem(
  target_circle_id uuid,
  target_role_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  role_row public.circle_roles%rowtype;
begin
  select r.* into role_row
  from public.circle_roles r
  where r.id = target_role_id
    and r.circle_id = target_circle_id;

  if role_row.id is null then
    return 'missing';
  end if;
  if role_row.is_default then
    return 'default';
  end if;
  if role_row.permissions & ~public.onboarding_safe_permissions() <> 0 then
    return 'permissions';
  end if;
  if exists (
    select 1
    from public.circle_roles other
    where other.circle_id = target_circle_id
      and other.position < role_row.position
      and other.permissions & ~public.onboarding_safe_permissions() <> 0
  ) then
    return 'rank';
  end if;
  return null;
end;
$$;

revoke execute on function public.onboarding_role_problem(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- The questions
-- ---------------------------------------------------------------------------

create table if not exists public.circle_onboarding_prompts (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  position integer not null default 0,
  title text not null,
  required boolean not null default false,
  single_select boolean not null default false,
  created_at timestamptz not null default now(),
  constraint circle_onboarding_prompts_title_length check (
    title = btrim(title) and char_length(title) between 1 and 100
  ),
  constraint circle_onboarding_prompts_id_circle_unique unique (id, circle_id)
);

create index if not exists circle_onboarding_prompts_circle_idx
  on public.circle_onboarding_prompts (circle_id, position);

create table if not exists public.circle_onboarding_options (
  id uuid primary key default gen_random_uuid(),
  prompt_id uuid not null,
  circle_id uuid not null,
  position integer not null default 0,
  label text not null,
  emoji text,
  created_at timestamptz not null default now(),
  constraint circle_onboarding_options_label_length check (
    label = btrim(label) and char_length(label) between 1 and 60
  ),
  constraint circle_onboarding_options_emoji_length check (
    emoji is null or char_length(emoji) between 1 and 16
  ),
  constraint circle_onboarding_options_id_circle_unique unique (id, circle_id),
  constraint circle_onboarding_options_prompt_fkey
    foreign key (prompt_id, circle_id)
    references public.circle_onboarding_prompts(id, circle_id)
    on delete cascade
);

create index if not exists circle_onboarding_options_prompt_idx
  on public.circle_onboarding_options (prompt_id, position);

create table if not exists public.circle_onboarding_option_roles (
  option_id uuid not null,
  circle_id uuid not null,
  role_id uuid not null,
  primary key (option_id, role_id),
  constraint circle_onboarding_option_roles_option_fkey
    foreign key (option_id, circle_id)
    references public.circle_onboarding_options(id, circle_id)
    on delete cascade,
  constraint circle_onboarding_option_roles_role_fkey
    foreign key (role_id, circle_id)
    references public.circle_roles(id, circle_id)
    on delete cascade
);

create index if not exists circle_onboarding_option_roles_role_idx
  on public.circle_onboarding_option_roles (role_id);

create table if not exists public.circle_onboarding_option_channels (
  option_id uuid not null,
  circle_id uuid not null,
  channel_id uuid not null,
  primary key (option_id, channel_id),
  constraint circle_onboarding_option_channels_option_fkey
    foreign key (option_id, circle_id)
    references public.circle_onboarding_options(id, circle_id)
    on delete cascade,
  constraint circle_onboarding_option_channels_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists circle_onboarding_option_channels_channel_idx
  on public.circle_onboarding_option_channels (channel_id);

-- Whatever writes a link, a role that cannot be handed out is refused.
create or replace function public.check_onboarding_option_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  problem text;
begin
  problem := public.onboarding_role_problem(new.circle_id, new.role_id);
  if problem is not null then
    raise exception 'This role cannot be given by an onboarding answer'
      using errcode = '22023', detail = 'role_' || problem;
  end if;
  return new;
end;
$$;

revoke execute on function public.check_onboarding_option_role()
  from public, anon, authenticated;

drop trigger if exists circle_onboarding_option_roles_check
  on public.circle_onboarding_option_roles;
create trigger circle_onboarding_option_roles_check
  before insert or update on public.circle_onboarding_option_roles
  for each row execute function public.check_onboarding_option_role();

-- A role that gains a management permission stops being something people
-- can pick: its links go, and so does the role of those who picked it.
create or replace function public.detach_onboarding_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  unlinked integer;
  taken_back integer;
begin
  if new.permissions & ~public.onboarding_safe_permissions() = 0 then
    return new;
  end if;

  delete from public.circle_onboarding_option_roles r
  where r.role_id = new.id;
  get diagnostics unlinked = row_count;

  delete from public.circle_member_roles mr
  where mr.role_id = new.id
    and mr.via_onboarding;
  get diagnostics taken_back = row_count;

  if (unlinked > 0 or taken_back > 0) and auth.uid() is not null then
    perform public.write_circle_audit(
      new.circle_id,
      'onboarding_update',
      'role',
      new.id,
      new.name,
      jsonb_build_object(
        'role_detached', true,
        'unlinked_options', unlinked,
        'taken_back', taken_back
      )
    );
  end if;
  return new;
end;
$$;

revoke execute on function public.detach_onboarding_role()
  from public, anon, authenticated;

drop trigger if exists circle_roles_detach_onboarding on public.circle_roles;
create trigger circle_roles_detach_onboarding
  after update of permissions on public.circle_roles
  for each row
  when (new.permissions is distinct from old.permissions)
  execute function public.detach_onboarding_role();

-- ---------------------------------------------------------------------------
-- The task list and the greeting
-- ---------------------------------------------------------------------------

create table if not exists public.circle_guide_tasks (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  position integer not null default 0,
  title text not null,
  action text not null,
  channel_id uuid,
  created_at timestamptz not null default now(),
  constraint circle_guide_tasks_title_length check (
    title = btrim(title) and char_length(title) between 1 and 80
  ),
  constraint circle_guide_tasks_action_check check (
    action in ('read_rules', 'visit_channel', 'send_message', 'set_avatar')
  ),
  -- Visiting needs a place to go; reading rules and the avatar have none.
  constraint circle_guide_tasks_channel_check check (
    case action
      when 'visit_channel' then channel_id is not null
      when 'send_message' then true
      else channel_id is null
    end
  ),
  constraint circle_guide_tasks_id_circle_unique unique (id, circle_id),
  constraint circle_guide_tasks_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade
);

create index if not exists circle_guide_tasks_circle_idx
  on public.circle_guide_tasks (circle_id, position);

-- greeting_channel_id: where a card announces each new member (null: off).
-- greeting_sticker_id: the sticker the card's "Say hello" button sends
-- (null: a waving hand). guide_since: when the circle first had a guide
-- (questions or tasks); only members who joined after that are shown it on
-- their own, the others find it in the circle menu.
create table if not exists public.circle_guide_settings (
  circle_id uuid primary key references public.circles(id) on delete cascade,
  greeting_channel_id uuid,
  greeting_sticker_id uuid references public.circle_emojis(id) on delete set null,
  guide_since timestamptz,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint circle_guide_settings_channel_fkey
    foreign key (greeting_channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete set null (greeting_channel_id)
);

-- ---------------------------------------------------------------------------
-- What each member did
-- ---------------------------------------------------------------------------

create table if not exists public.circle_member_onboarding (
  circle_id uuid not null,
  user_id uuid not null,
  answered_at timestamptz,
  dismissed_at timestamptz,
  primary key (circle_id, user_id),
  constraint circle_member_onboarding_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade
);

create table if not exists public.circle_member_onboarding_answers (
  circle_id uuid not null,
  user_id uuid not null,
  option_id uuid not null,
  primary key (circle_id, user_id, option_id),
  constraint circle_member_onboarding_answers_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade,
  constraint circle_member_onboarding_answers_option_fkey
    foreign key (option_id, circle_id)
    references public.circle_onboarding_options(id, circle_id)
    on delete cascade
);

create index if not exists circle_member_onboarding_answers_option_idx
  on public.circle_member_onboarding_answers (option_id);

create table if not exists public.circle_member_guide_tasks (
  circle_id uuid not null,
  user_id uuid not null,
  task_id uuid not null,
  completed_at timestamptz not null default now(),
  primary key (circle_id, user_id, task_id),
  constraint circle_member_guide_tasks_member_fkey
    foreign key (circle_id, user_id)
    references public.circle_members(circle_id, user_id)
    on delete cascade,
  constraint circle_member_guide_tasks_task_fkey
    foreign key (task_id, circle_id)
    references public.circle_guide_tasks(id, circle_id)
    on delete cascade
);

create index if not exists circle_member_guide_tasks_task_idx
  on public.circle_member_guide_tasks (task_id);

-- Closed to clients: everything goes through the RPCs of part 2.
alter table public.circle_onboarding_prompts enable row level security;
alter table public.circle_onboarding_options enable row level security;
alter table public.circle_onboarding_option_roles enable row level security;
alter table public.circle_onboarding_option_channels enable row level security;
alter table public.circle_guide_tasks enable row level security;
alter table public.circle_guide_settings enable row level security;
alter table public.circle_member_onboarding enable row level security;
alter table public.circle_member_onboarding_answers enable row level security;
alter table public.circle_member_guide_tasks enable row level security;

revoke all on public.circle_onboarding_prompts from public, anon, authenticated;
revoke all on public.circle_onboarding_options from public, anon, authenticated;
revoke all on public.circle_onboarding_option_roles from public, anon, authenticated;
revoke all on public.circle_onboarding_option_channels from public, anon, authenticated;
revoke all on public.circle_guide_tasks from public, anon, authenticated;
revoke all on public.circle_guide_settings from public, anon, authenticated;
revoke all on public.circle_member_onboarding from public, anon, authenticated;
revoke all on public.circle_member_onboarding_answers from public, anon, authenticated;
revoke all on public.circle_member_guide_tasks from public, anon, authenticated;
