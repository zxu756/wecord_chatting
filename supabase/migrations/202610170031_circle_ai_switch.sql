-- A circle can turn the AI features (catch-up summaries, rewriting,
-- translating) off for everyone in it.
--
-- * circles.ai_enabled: on by default. Members read it with the rest of the
--   circle.
-- * set_circle_ai_enabled(circle, enabled): members with manage_circle
--   change it; audited as circle_ai_update.
-- * conversation_ai_allowed(conversation): false only when the conversation
--   is a channel of a circle (or a thread of one) the caller belongs to and
--   that circle has AI off. The `ai` Edge Function asks it as the caller
--   before using a circle's messages (and answers ai_disabled_in_circle).
--   Direct chats, groups and conversations the caller is not part of are
--   not circle-gated.

alter table public.circles
  add column if not exists ai_enabled boolean not null default true;

create or replace function public.set_circle_ai_enabled(
  target_circle_id uuid,
  enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  circle public.circles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if enabled is null then
    raise exception 'Choose on or off' using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can change AI features'
      using errcode = '42501';
  end if;

  select c.* into circle
  from public.circles c
  where c.id = target_circle_id
  for update;

  if not found then
    raise exception 'Circle not found' using errcode = 'P0002';
  end if;

  if circle.ai_enabled = enabled then
    return circle.ai_enabled;
  end if;

  update public.circles c
  set ai_enabled = enabled
  where c.id = circle.id;

  perform public.write_circle_audit(
    circle.id,
    'circle_ai_update',
    'circle',
    circle.id,
    circle.name,
    jsonb_build_object(
      'ai_enabled', jsonb_build_object('old', circle.ai_enabled, 'new', enabled)
    )
  );

  return enabled;
end;
$$;

create or replace function public.conversation_ai_allowed(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select c.ai_enabled or not public.is_current_user_circle_member(c.id)
      from public.circle_channels cc
      join public.circles c on c.id = cc.circle_id
      where cc.conversation_id = coalesce(
        (
          select ct.parent_conversation_id
          from public.conversation_threads ct
          where ct.conversation_id = target_conversation_id
        ),
        target_conversation_id
      )
      limit 1
    ),
    true
  );
$$;

revoke execute on function public.set_circle_ai_enabled(uuid, boolean) from public;
revoke execute on function public.set_circle_ai_enabled(uuid, boolean) from anon;
grant execute on function public.set_circle_ai_enabled(uuid, boolean) to authenticated;

revoke execute on function public.conversation_ai_allowed(uuid) from public;
revoke execute on function public.conversation_ai_allowed(uuid) from anon;
grant execute on function public.conversation_ai_allowed(uuid) to authenticated;
