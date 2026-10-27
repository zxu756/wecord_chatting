-- Workflow automation (roadmap D9), part 1 of 5: the tables and the limits.
--
-- A workflow is a rule a group's owner or admin, or a circle's manager
-- (manage_circle), sets up once: "when a member joins -> thank them in
-- #welcome and give the role", "when someone reacts with a check mark -> make
-- a task", "every Friday at 9 -> post the weekly form".
--
--   trigger   member_joined | reaction | keyword | schedule | form_submitted
--   actions   one to five, in order: send_message | send_dm | add_role |
--             create_task | send_form
--   scope     one circle (circle_id) or one group chat (conversation_id)
--
-- How it runs (parts 3 and 4):
--   * The event (a join, a reaction, a message, a response, the clock) only
--     writes a row into workflow_runs, in the transaction of whoever caused
--     it. It never raises, never waits, and is skipped while a workflow is
--     running (so a workflow cannot start another one: no loops).
--   * A job of its own (pg_cron, every minute: run_workflow_tick) takes the
--     queued runs, checks the creator can still do this, and does each action
--     AS THE CREATOR, through the same functions the creator's own app would
--     call (send_text_message, set_member_roles, create_form,
--     upsert_task_item ...). So blocking, timeouts, slowmode, AutoMod, the AI
--     guard, channel permissions, role ranks, a suspended circle (K1) and
--     the private-chat rules (G6) apply exactly as they do to the creator.
--     Messages a workflow sends are marked auto_reply (the app labels them).
--   * When the creator stops being allowed to manage the workflow's scope
--     (left, demoted, removed, account deleted), the workflow pauses itself.
--     Whoever turns it back on becomes the person it runs as.
--   * run_later_dispatch() is not touched; the push for the messages a
--     workflow sent is claimed by scheduled-dispatch (part 4).
--
-- Limits (workflow_limits()): 20 workflows per circle, 5 per group; 5 actions
-- per workflow; 200 runs a day per workflow and 1000 a day per circle or
-- group; 10 runs a day per workflow for one member; 500 characters per text.
--
-- Everything is closed to clients: they read and change workflows only
-- through the functions of part 2, which check who they are.

create table if not exists public.workflows (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid references public.circles(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete cascade,
  name text not null,
  trigger_kind text not null,
  trigger_config jsonb not null default '{}'::jsonb,
  actions jsonb not null,
  enabled boolean not null default true,
  -- manual | creator_lost_permission | creator_gone | failures | finished
  paused_reason text,
  paused_at timestamptz,
  -- Who the actions run as; null once that person's account is gone.
  created_by uuid references public.profiles(id) on delete set null,
  -- schedule: when it runs next.
  next_run_at timestamptz,
  last_run_at timestamptz,
  -- Runs that failed one after the other; five pause the workflow.
  fail_streak integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workflows_one_scope check (
    (circle_id is not null)::integer + (conversation_id is not null)::integer = 1
  ),
  constraint workflows_name_length check (char_length(name) between 1 and 60),
  constraint workflows_trigger_kind check (
    trigger_kind in ('member_joined', 'reaction', 'keyword', 'schedule', 'form_submitted')
  ),
  constraint workflows_trigger_config check (
    jsonb_typeof(trigger_config) = 'object'
    and octet_length(trigger_config::text) <= 2048
  ),
  constraint workflows_actions check (
    jsonb_typeof(actions) = 'array'
    and jsonb_array_length(actions) between 1 and 5
    and octet_length(actions::text) <= 8192
  ),
  constraint workflows_paused_reason check (
    paused_reason is null
    or paused_reason in (
      'manual', 'creator_lost_permission', 'creator_gone', 'failures', 'finished'
    )
  ),
  constraint workflows_paused_has_reason check (enabled or paused_reason is not null)
);

create index if not exists workflows_circle_idx
  on public.workflows (circle_id) where circle_id is not null;
create index if not exists workflows_conversation_idx
  on public.workflows (conversation_id) where conversation_id is not null;
-- The events look workflows up by what they listen for.
create index if not exists workflows_listen_idx
  on public.workflows (trigger_kind, circle_id, conversation_id) where enabled;
create index if not exists workflows_form_idx
  on public.workflows (((trigger_config ->> 'form_id')))
  where enabled and trigger_kind = 'form_submitted';
create index if not exists workflows_due_idx
  on public.workflows (next_run_at)
  where enabled and trigger_kind = 'schedule';
create index if not exists workflows_creator_idx
  on public.workflows (created_by) where created_by is not null;

create table if not exists public.workflow_runs (
  id uuid primary key default gen_random_uuid(),
  workflow_id uuid not null references public.workflows(id) on delete cascade,
  -- What the run is for, so the same event never runs twice: 'join:<user>:<ms>',
  -- 'react:<message>', 'kw:<message>', 'form:<response>', 'sched:<epoch>'.
  event_key text not null,
  -- The member the event is about (the one who joined, reacted, wrote or
  -- answered); null for the clock.
  actor_id uuid references public.profiles(id) on delete set null,
  -- {message_id, conversation_id, channel_id, form_id, response_id}: ids only,
  -- never what was said.
  subject jsonb not null default '{}'::jsonb,
  status text not null default 'queued',
  -- Why a whole run was not done: paused | circle_suspended | expired |
  -- creator_lost_permission | missed | daily_limit.
  skip_reason text,
  -- One entry per action: {action, status: ok|skipped|failed, detail}.
  results jsonb not null default '[]'::jsonb,
  error text,
  -- clock_timestamp, not now(): runs of one transaction keep their order.
  created_at timestamptz not null default clock_timestamp(),
  started_at timestamptz,
  finished_at timestamptz,
  constraint workflow_runs_status check (
    status in ('queued', 'running', 'succeeded', 'failed', 'skipped')
  ),
  constraint workflow_runs_event_key_length check (char_length(event_key) <= 200),
  constraint workflow_runs_once unique (workflow_id, event_key)
);

create index if not exists workflow_runs_queue_idx
  on public.workflow_runs (created_at) where status = 'queued';
create index if not exists workflow_runs_workflow_idx
  on public.workflow_runs (workflow_id, created_at desc);
create index if not exists workflow_runs_actor_idx
  on public.workflow_runs (actor_id) where actor_id is not null;

-- The messages a workflow sent that still need their push (claimed once by
-- the scheduled-dispatch function, which then asks claim_push_delivery as for
-- any message).
create table if not exists public.workflow_push_queue (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  claimed_at timestamptz
);

create index if not exists workflow_push_queue_waiting_idx
  on public.workflow_push_queue (created_at) where claimed_at is null;

alter table public.workflows enable row level security;
alter table public.workflow_runs enable row level security;
alter table public.workflow_push_queue enable row level security;

revoke all on public.workflows from anon, authenticated;
revoke all on public.workflow_runs from anon, authenticated;
revoke all on public.workflow_push_queue from anon, authenticated;

-- ------------------------------------------------------------------ limits

create or replace function public.workflow_limits()
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'max_per_circle', 20,
    'max_per_group', 5,
    'max_actions', 5,
    'max_runs_per_day', 200,
    'max_scope_runs_per_day', 1000,
    'max_member_runs_per_day', 10,
    'max_text', 500,
    'max_keywords', 10
  );
$$;

-- A pure list of numbers: the app shows them, so signed-in people may read.
revoke execute on function public.workflow_limits() from public, anon;
grant execute on function public.workflow_limits() to authenticated, service_role;

-- ---------------------------------------------------------- who may manage

-- Whether [p_user_id] may create and change the workflows of a circle or a
-- group, and so be the person a workflow runs as: in a circle, a member with
-- manage_circle (the owner and administrators have it), in a circle that is
-- not suspended (K1); in a group, its owner or an admin. Never a deleted or
-- suspended account.
create or replace function public.workflow_user_can_manage(
  p_circle_id uuid,
  p_conversation_id uuid,
  p_user_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    return false;
  end if;
  if exists (
    select 1 from public.profiles p
    where p.id = p_user_id and (p.deleted_at is not null or p.is_bot)
  ) or public.is_user_suspended(p_user_id) then
    return false;
  end if;

  if p_circle_id is not null then
    return not public.circle_is_suspended(p_circle_id)
      and public.circle_member_has_permission(p_circle_id, p_user_id, 'manage_circle');
  end if;

  if p_conversation_id is not null then
    return exists (
      select 1
      from public.conversation_members cm
      join public.conversations c on c.id = cm.conversation_id
      where cm.conversation_id = p_conversation_id
        and cm.user_id = p_user_id
        and cm.role in ('owner', 'admin')
        and c.type = 'group'
    );
  end if;
  return false;
end;
$$;

revoke execute on function public.workflow_user_can_manage(uuid, uuid, uuid)
  from public, anon, authenticated;

-- The roles a workflow may hand out on its own: none that can moderate,
-- manage or mention everyone. (Handing out a role is also held to the
-- creator's own rank by set_member_roles at run time.)
create or replace function public.workflow_role_grantable(p_role_id uuid, p_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_roles r
    where r.id = p_role_id
      and r.circle_id = p_circle_id
      and not r.is_default
      and r.permissions & public.circle_permission_bits(array[
        'manage_messages', 'manage_channels', 'manage_roles', 'kick_members',
        'mention_everyone', 'manage_webhooks', 'view_audit_log',
        'administrator', 'ban_members', 'moderate_members', 'manage_circle'
      ]) = 0
  );
$$;

revoke execute on function public.workflow_role_grantable(uuid, uuid)
  from public, anon, authenticated;
