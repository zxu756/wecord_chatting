-- Task lists 2.0 (D7), part 4: the data export.
--
-- export_my_task_extras(user) is for the data-export Edge Function (service
-- role only). The task lists in export_my_extras (202610190023) keep working
-- as they were; this adds what 2.0 stores, for the same things: the fields
-- of the lists the person made, and for the tasks they created, their
-- values (named by the field, people by name), the task they are a subtask
-- of and their repeat rule.

create or replace function public.export_my_task_extras(target_user_id uuid)
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
    'lists', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', l.id,
          'conversation_id', l.conversation_id,
          'title', l.title,
          'created_by_me', l.created_by = target_user_id,
          'fields', case when l.created_by = target_user_id then l.field_defs end,
          'items', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', i.id,
                'title', i.title,
                'parent_id', i.parent_id,
                'repeat', i.recurrence,
                'values', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'field', d->>'name',
                      'type', d->>'type',
                      'value', case d->>'type'
                        when 'person' then public.export_person_json((i.custom->>(d->>'id'))::uuid)
                        when 'select' then to_jsonb((
                          select o->>'name'
                          from jsonb_array_elements(d->'options') o
                          where o->>'id' = i.custom->>(d->>'id')
                        ))
                        else i.custom->(d->>'id')
                      end
                    )
                  )
                  from jsonb_array_elements(l.field_defs) d
                  where i.custom ? (d->>'id')
                ), '[]'::jsonb)
              )
              order by i.created_at, i.id
            )
            from (
              select *
              from public.task_items ti
              where ti.list_id = l.id
                and ti.deleted_at is null
                and ti.created_by = target_user_id
              order by ti.created_at, ti.id
              limit 2000
            ) i
          ), '[]'::jsonb)
        )
        order by l.created_at desc, l.id
      )
      from (
        select *
        from public.task_lists tl
        where tl.deleted_at is null
          and (
            tl.created_by = target_user_id
            or exists (
              select 1
              from public.task_items ti
              where ti.list_id = tl.id
                and ti.deleted_at is null
                and ti.created_by = target_user_id
            )
          )
        order by tl.created_at desc, tl.id desc
        limit 1000
      ) l
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_task_extras(uuid) from public, anon, authenticated;
grant execute on function public.export_my_task_extras(uuid) to service_role;
