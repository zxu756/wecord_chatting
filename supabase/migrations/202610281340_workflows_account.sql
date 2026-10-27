-- Workflow automation (roadmap D9), part 5 of 5: leaving WeCord and taking
-- your data.
--
-- * Deleting an account (profiles.deleted_at):
--     - the workflows the person made stay with their circle or group, but
--       pause themselves (creator_gone) and have no creator: they cannot run
--       as nobody. A manager who turns one back on becomes the person it
--       runs as (set_workflow_enabled);
--     - the person is taken out of the run log (actor_id), and the runs still
--       waiting for them are dropped;
--     - messages a workflow sent AS them are theirs like any message and go
--       with the rest of their messages.
--   Same pattern as profiles_erase_events2 (202610270470);
--   prepare_account_deletion is not rewritten.
-- * export_my_workflows(user) is for the data-export Edge Function (service
--   role only, like export_my_events2): the workflows the person made, with
--   what they listen for and do, and the times a workflow ran because of
--   them (which workflow, when, what happened) but nothing others did.

create or replace function public.erase_workflows_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.workflows
  set enabled = false,
      paused_reason = 'creator_gone',
      paused_at = now(),
      next_run_at = null,
      created_by = null,
      updated_at = now()
  where created_by = new.id;

  delete from public.workflow_runs
  where actor_id = new.id and status = 'queued';
  update public.workflow_runs set actor_id = null where actor_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_workflows_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_workflows on public.profiles;
create trigger profiles_erase_workflows
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_workflows_of_deleted_account();

create or replace function public.export_my_workflows(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'workflows_made', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'name', w.name,
          'where', case
            when w.circle_id is not null then (
              select c.name from public.circles c
              where c.id = w.circle_id
                and exists (
                  select 1 from public.circle_members cm
                  where cm.circle_id = c.id and cm.user_id = target_user_id
                )
            )
            else (
              select coalesce(nullif(c.title, ''), c.type)
              from public.conversations c
              join public.conversation_members cm
                on cm.conversation_id = c.id and cm.user_id = target_user_id
              where c.id = w.conversation_id
            )
          end,
          'trigger', w.trigger_kind,
          'trigger_config', w.trigger_config,
          'actions', w.actions,
          'running', w.enabled,
          'paused_reason', w.paused_reason,
          'created_at', w.created_at
        )
        order by w.created_at desc, w.id
      )
      from public.workflows w
      where w.created_by = target_user_id
    ), '[]'::jsonb),
    'runs_about_me', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'workflow', q.name,
          'status', q.status,
          'at', q.created_at
        )
        order by q.created_at desc
      )
      from (
        select w.name, r.status, r.created_at
        from public.workflow_runs r
        join public.workflows w on w.id = r.workflow_id
        where r.actor_id = target_user_id
        order by r.created_at desc
        limit 1000
      ) q
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_workflows(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_workflows(uuid) to service_role;
