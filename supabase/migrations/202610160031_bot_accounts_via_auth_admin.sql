-- Bot accounts are made by the `bots` Edge Function with the Auth admin
-- API (service role) instead of an insert into auth.users from SQL, which
-- hosted projects may not allow. The function creates a banned login with
-- provider 'bot', then calls create_circle_bot as the caller, which checks
-- the caller's permissions as before and takes over that login.

drop function if exists public.create_circle_bot(uuid, text, uuid);

create or replace function public.create_circle_bot(
  target_circle_id uuid,
  bot_name text,
  target_role_id uuid,
  bot_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := btrim(coalesce(bot_name, ''));
  given_role public.circle_roles%rowtype;
  token text := public.new_webhook_token();
  created public.circle_bots%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(target_circle_id, 'manage_circle') then
    raise exception 'Only members who manage the circle can add bots'
      using errcode = '42501';
  end if;

  if char_length(trimmed_name) not between 1 and 32 then
    raise exception 'Bot name must be 1 to 32 characters' using errcode = '22023';
  end if;

  if target_role_id is not null then
    select r.* into given_role
    from public.circle_roles r
    where r.id = target_role_id
      and r.circle_id = target_circle_id
      and not r.is_default;

    if given_role.id is null
      or not public.current_user_has_circle_permission(target_circle_id, 'manage_roles')
      or given_role.position >= public.circle_member_rank(target_circle_id, current_user_id)
    then
      raise exception 'You cannot give this role' using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bots:' || target_circle_id::text, 0));

  if (
    select count(*) from public.circle_bots b where b.circle_id = target_circle_id
  ) >= 10 then
    raise exception 'A circle can have at most 10 bots' using errcode = '54000';
  end if;

  -- The bots Edge Function made this login with the service role just
  -- before: banned, provider 'bot' in its app metadata (which only the
  -- service role can set), and not yet anyone's profile.
  if bot_user_id is null
    or not exists (
      select 1
      from auth.users u
      where u.id = bot_user_id
        and u.raw_app_meta_data->>'provider' = 'bot'
        and u.created_at > now() - interval '10 minutes'
    )
    or exists (select 1 from public.profiles p where p.id = bot_user_id)
  then
    raise exception 'The bot account is not ready' using errcode = '22023';
  end if;

  insert into public.profiles (id, username, display_name, is_bot)
  values (
    bot_user_id,
    'bot_' || substr(replace(bot_user_id::text, '-', ''), 1, 12),
    trimmed_name,
    true
  );

  -- Added by a manager, so the circle's rules (202610160021) count as
  -- accepted.
  insert into public.circle_members (circle_id, user_id, role, rules_accepted_at)
  values (target_circle_id, bot_user_id, 'member', now());

  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, bot_user_id, 'member'
  from public.circle_channels cc
  where cc.circle_id = target_circle_id
  on conflict do nothing;

  if given_role.id is not null then
    insert into public.circle_member_roles (circle_id, user_id, role_id)
    values (target_circle_id, bot_user_id, given_role.id);
    perform public.sync_circle_admin_roles(target_circle_id);
  end if;

  insert into public.circle_bots (circle_id, user_id, name, token_hash, created_by)
  values (
    target_circle_id,
    bot_user_id,
    trimmed_name,
    public.webhook_token_hash(token),
    current_user_id
  )
  returning * into created;

  perform public.write_circle_audit(
    target_circle_id,
    'bot_create',
    'bot',
    created.id,
    created.name,
    jsonb_strip_nulls(jsonb_build_object('role_name', given_role.name))
  );

  return public.circle_bot_payload(created) || jsonb_build_object('token', token);
end;
$$;

revoke execute on function public.create_circle_bot(uuid, text, uuid, uuid) from public, anon;
grant execute on function public.create_circle_bot(uuid, text, uuid, uuid) to authenticated;
