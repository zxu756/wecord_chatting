-- "Download my data" (202610170053, 202610190023): forms and collection sheets
-- (D1, 202610230100-202610230120).
--
-- export_my_forms(user), for the data-export Edge Function (service role only,
-- like export_my_extras). Like the other export functions it starts from the
-- person it is asked about and reads only what that person wrote:
--
--   * the forms I created: the title, description, questions, settings, the
--     number of answers and the deadline, but NOT the answers of other people
--     (and so never who answered an anonymous form);
--   * the forms I answered: the title and the questions (they are what my
--     answers answer), who made the form (name only) and MY answer sheets
--     (every one, when the form took several), with the pictures I uploaded
--     named by bucket and path so the export can link them.
--
-- A new function: export_my_extras is not rewritten. Capped at 2000 forms.

create or replace function public.export_my_forms(target_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if target_user_id is null then
    raise exception 'A user is required' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', f.id,
      'conversation_id', f.conversation_id,
      'title', f.title,
      'created_by_me', f.creator_id = target_user_id,
      'creator', public.export_person_json(f.creator_id),
      'description', case when f.creator_id = target_user_id then f.description end,
      'settings', case when f.creator_id = target_user_id then f.settings end,
      'response_count', case when f.creator_id = target_user_id then f.response_count end,
      'questions', (
        select coalesce(jsonb_agg(
          jsonb_build_object(
            'id', q->>'id',
            'type', q->>'type',
            'label', q->>'label',
            'options', q->'options'
          )
        ), '[]'::jsonb)
        from jsonb_array_elements(f.fields) q
      ),
      'closed_at', f.closed_at,
      'created_at', f.created_at,
      'my_responses', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'answers', r.answers,
            'submitted_at', r.submitted_at,
            'updated_at', r.updated_at
          )
          order by r.submitted_at, r.id
        )
        from public.form_responses r
        where r.form_id = f.id and r.user_id = target_user_id
      ), '[]'::jsonb)
    )
    order by f.created_at desc, f.id
  ), '[]'::jsonb)
  into result
  from (
    select *
    from public.forms ff
    where ff.creator_id = target_user_id
      or exists (
        select 1
        from public.form_responses r
        where r.form_id = ff.id and r.user_id = target_user_id
      )
    order by ff.created_at desc, ff.id desc
    limit 2000
  ) f;

  return result;
end;
$$;

revoke execute on function public.export_my_forms(uuid) from public;
revoke execute on function public.export_my_forms(uuid) from anon;
revoke execute on function public.export_my_forms(uuid) from authenticated;
