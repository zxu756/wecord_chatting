-- "Download my data" (202610170053, 202610230130): the daily digest settings
-- (F3, 202610230500).
--
-- export_my_ai_digest(user), for the data-export Edge Function (service role
-- only, like export_my_forms): whether the digest is on, the time and language
-- the person chose, the time zone it runs in, and the chats they follow (name
-- only). The finished digests are not included: they are short-lived (two
-- weeks) summaries of other people's messages, not the person's own data.
--
-- A new function: export_my_extras is not rewritten.

create or replace function public.export_my_ai_digest(target_user_id uuid)
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
    'enabled', coalesce(
      (select s.enabled from public.ai_digest_settings s where s.user_id = target_user_id),
      false
    ),
    'deliver_at', (
      select to_char(s.deliver_at, 'HH24:MI')
      from public.ai_digest_settings s
      where s.user_id = target_user_id
    ),
    'language', (
      select s.language from public.ai_digest_settings s where s.user_id = target_user_id
    ),
    'time_zone', public.notification_time_zone(target_user_id),
    'subscriptions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conversation_id', sub.conversation_id,
          'name', coalesce(cc.name, c.title),
          'circle', ci.name,
          'since', sub.created_at
        )
        order by sub.created_at, sub.conversation_id
      )
      from public.ai_digest_subscriptions sub
      join public.conversations c on c.id = sub.conversation_id
      left join public.circle_channels cc on cc.conversation_id = sub.conversation_id
      left join public.circles ci on ci.id = cc.circle_id
      where sub.user_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_ai_digest(uuid) from public, anon, authenticated;
grant execute on function public.export_my_ai_digest(uuid) to service_role;
