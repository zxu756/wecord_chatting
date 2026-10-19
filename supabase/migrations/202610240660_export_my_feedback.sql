-- "Download my data" (202610170053, 202610190023, 202610230130): feedback and
-- help (K7, 202610240640-202610240650).
--
-- export_my_feedback(user), for the data-export Edge Function (service role
-- only, like export_my_forms). It reads only what the person wrote and what
-- the team answered them: the message, the app version and platform it
-- carried, the status, the screenshot (named by bucket and path so the export
-- can link it) and the replies. Nothing an admin wrote about anybody else.
--
-- A new function: export_my_extras is not rewritten. Capped at 500 pieces of
-- feedback.

create or replace function public.export_my_feedback(target_user_id uuid)
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
      'message', f.message,
      'app_version', f.app_version,
      'platform', f.platform,
      'status', f.status,
      'created_at', f.created_at,
      'replied_at', f.replied_at,
      'screenshot_bucket', case
        when f.screenshot_path is not null then 'feedback-screenshots'
      end,
      'screenshot_path', f.screenshot_path,
      'replies', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'body', coalesce(nullif(a.body_en, ''), a.body_zh),
            'published_at', a.published_at
          )
          order by a.published_at
        )
        from public.announcements a
        where a.feedback_id = f.id
          and a.audience_user_id = target_user_id
          and a.retracted_at is null
      ), '[]'::jsonb)
    )
    order by f.created_at desc, f.id
  ), '[]'::jsonb)
  into result
  from (
    select *
    from public.user_feedback ff
    where ff.user_id = target_user_id
    order by ff.created_at desc, ff.id desc
    limit 500
  ) f;

  return result;
end;
$$;

revoke execute on function public.export_my_feedback(uuid) from public;
revoke execute on function public.export_my_feedback(uuid) from anon;
revoke execute on function public.export_my_feedback(uuid) from authenticated;
