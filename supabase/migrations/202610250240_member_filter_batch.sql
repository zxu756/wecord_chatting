-- Moderator tools 2.0 (C5), part 5 of 9: finding members and acting on many.
--
-- * list_circle_members_for_moderation: the member list a moderator filters:
--   by when they joined, how old their account is, how much they have said,
--   a role, whether they are flagged (a warning, an open report, or a
--   message the AI guard held or flagged), and by name. Pages of up to 100.
--   For each row it also says what the caller may do to that person (time
--   out, kick, ban), by the same permission and rank rules the single
--   actions use, so the app can grey out a row instead of failing later.
--   Needs moderate_members, kick_members or ban_members.
-- * batch_moderate_circle_members: time out (or end a timeout), kick or ban
--   up to 50 people in one call. It does not reimplement anything: each
--   person goes through timeout_circle_member / kick_circle_member /
--   ban_circle_member inside its own sub-transaction, so the permission, the
--   rank rule ("nobody ranked at or above you"), the owner and administrator
--   protection and each action's own audit entry all apply, and one refusal
--   (a higher-ranked person in the selection) does not stop the others. The
--   answer lists what happened to each person; bans also return the files of
--   deleted messages for the app to remove from Storage. One more audit
--   entry, member_batch_action, says how many were acted on. Refused while a
--   platform admin has the circle down (K1).

create or replace function public.list_circle_members_for_moderation(
  target_circle_id uuid,
  joined_within_days integer default null,
  joined_before_days integer default null,
  account_within_days integer default null,
  min_messages integer default null,
  max_messages integer default null,
  filter_role_id uuid default null,
  only_flagged boolean default false,
  name_query text default null,
  result_limit integer default 50,
  result_offset integer default 0
)
returns table (
  user_id uuid,
  username text,
  display_name text,
  nickname text,
  avatar_url text,
  member_role text,
  joined_at timestamptz,
  account_created_at timestamptz,
  message_count integer,
  warning_count integer,
  flagged boolean,
  timed_out_until timestamptz,
  role_ids uuid[],
  can_timeout boolean,
  can_kick boolean,
  can_ban boolean,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_rank integer;
  may_timeout boolean;
  may_kick boolean;
  may_ban boolean;
  need_counts boolean;
  query_text text := nullif(btrim(coalesce(name_query, '')), '');
  max_rows integer := least(greatest(coalesce(result_limit, 50), 1), 100);
  skip_rows integer := greatest(coalesce(result_offset, 0), 0);
  channel_conversations uuid[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  may_timeout := public.current_user_has_circle_permission(
    target_circle_id, 'moderate_members');
  may_kick := public.current_user_has_circle_permission(
    target_circle_id, 'kick_members');
  may_ban := public.current_user_has_circle_permission(
    target_circle_id, 'ban_members');
  if not (may_timeout or may_kick or may_ban) then
    raise exception 'Only moderators can filter members' using errcode = '42501';
  end if;

  caller_rank := public.circle_member_rank(target_circle_id, current_user_id);
  need_counts := min_messages is not null or max_messages is not null;

  select coalesce(array_agg(x.conversation_id), '{}')
  into channel_conversations
  from (
    select cc.conversation_id
    from public.circle_channels cc
    where cc.circle_id = target_circle_id
    union all
    select ct.conversation_id
    from public.conversation_threads ct
    join public.circle_channels cc
      on cc.conversation_id = ct.parent_conversation_id
    where cc.circle_id = target_circle_id
  ) x;

  return query
  with base as (
    select
      cm.user_id as uid,
      p.username as uname,
      p.display_name as dname,
      cm.nickname as nick,
      p.avatar_url as avatar,
      cm.role as mrole,
      cm.created_at as joined,
      p.created_at as account_created,
      cm.timed_out_until as timed_out,
      coalesce((
        select array_agg(mr.role_id)
        from public.circle_member_roles mr
        where mr.circle_id = cm.circle_id
          and mr.user_id = cm.user_id
      ), '{}') as roles,
      (
        select count(*)::integer
        from public.circle_mod_notes n
        where n.circle_id = cm.circle_id
          and n.user_id = cm.user_id
          and n.kind = 'warning'
      ) as warnings,
      case when need_counts then (
        select count(*)::integer
        from public.messages m
        where m.sender_id = cm.user_id
          and m.conversation_id = any (channel_conversations)
          and m.recalled_at is null
          and m.type <> 'system'
      ) end as counted,
      c.owner_id = cm.user_id as is_owner,
      public.circle_member_rank(cm.circle_id, cm.user_id) as rank
    from public.circle_members cm
    join public.circles c on c.id = cm.circle_id
    join public.profiles p on p.id = cm.user_id
    where cm.circle_id = target_circle_id
      and not p.is_bot
      and (joined_within_days is null
        or cm.created_at >= now() - make_interval(days => joined_within_days))
      and (joined_before_days is null
        or cm.created_at < now() - make_interval(days => joined_before_days))
      and (account_within_days is null
        or p.created_at >= now() - make_interval(days => account_within_days))
      and (filter_role_id is null or exists (
        select 1
        from public.circle_member_roles mr
        where mr.circle_id = cm.circle_id
          and mr.user_id = cm.user_id
          and mr.role_id = filter_role_id
      ))
      and (query_text is null
        or p.username ilike '%' || replace(replace(query_text, '%', ''), '_', '\_') || '%'
        or p.display_name ilike '%' || replace(replace(query_text, '%', ''), '_', '\_') || '%'
        or cm.nickname ilike '%' || replace(replace(query_text, '%', ''), '_', '\_') || '%')
  ),
  flagged_base as (
    select
      b.*,
      (
        b.warnings > 0
        or exists (
          select 1
          from public.message_reports r
          where r.circle_id = target_circle_id
            and r.reported_user_id = b.uid
            and r.status = 'open'
        )
        or exists (
          select 1
          from public.message_reviews mrv
          where mrv.circle_id = target_circle_id
            and mrv.sender_id = b.uid
            and mrv.state in ('held', 'flagged')
        )
      ) as is_flagged
    from base b
    where (min_messages is null or b.counted >= min_messages)
      and (max_messages is null or b.counted <= max_messages)
  ),
  filtered as (
    select f.*, count(*) over () as total
    from flagged_base f
    where not only_flagged or f.is_flagged
    order by f.joined desc, f.uid
    limit max_rows offset skip_rows
  )
  select
    f.uid,
    f.uname,
    f.dname,
    f.nick,
    f.avatar,
    f.mrole,
    f.joined,
    f.account_created,
    coalesce(f.counted, (
      select count(*)::integer
      from public.messages m
      where m.sender_id = f.uid
        and m.conversation_id = any (channel_conversations)
        and m.recalled_at is null
        and m.type <> 'system'
    )),
    f.warnings,
    f.is_flagged,
    case when f.timed_out > now() then f.timed_out end,
    f.roles,
    may_timeout
      and f.uid <> current_user_id
      and not f.is_owner
      and f.rank < caller_rank
      and not exists (
        select 1
        from public.circle_roles r
        where r.circle_id = target_circle_id
          and r.permissions & 16384 <> 0
          and (r.is_default or r.id = any (f.roles))
      ),
    may_kick
      and f.uid <> current_user_id
      and not f.is_owner
      and f.rank < caller_rank,
    may_ban
      and f.uid <> current_user_id
      and not f.is_owner
      and f.rank < caller_rank,
    f.total
  from filtered f
  order by f.joined desc, f.uid;
end;
$$;

create or replace function public.batch_moderate_circle_members(
  target_circle_id uuid,
  target_user_ids uuid[],
  batch_action text,
  duration_seconds integer default null,
  batch_reason text default null,
  delete_message_hours integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  ids uuid[];
  one_id uuid;
  results jsonb := '[]'::jsonb;
  media jsonb := '[]'::jsonb;
  done integer := 0;
  media_row record;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if batch_action is null
    or batch_action not in ('timeout', 'untimeout', 'kick', 'ban')
  then
    raise exception 'Unknown action' using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    case batch_action
      when 'kick' then 'kick_members'
      when 'ban' then 'ban_members'
      else 'moderate_members'
    end
  ) then
    raise exception 'You do not have the permission for this action'
      using errcode = '42501';
  end if;

  perform public.assert_circle_up(target_circle_id);

  select coalesce(array_agg(distinct u), '{}')
  into ids
  from unnest(coalesce(target_user_ids, '{}')) u
  where u is not null;

  if cardinality(ids) = 0 then
    raise exception 'Choose at least one member' using errcode = '22023';
  end if;
  if cardinality(ids) > 50 then
    raise exception 'Up to 50 members at a time' using errcode = '22023';
  end if;
  if batch_action = 'timeout'
    and (duration_seconds is null or duration_seconds not between 1 and 2419200)
  then
    raise exception 'Timeouts last up to 28 days' using errcode = '22023';
  end if;

  foreach one_id in array ids loop
    begin
      if batch_action = 'timeout' then
        perform public.timeout_circle_member(
          target_circle_id, one_id, duration_seconds);
      elsif batch_action = 'untimeout' then
        perform public.timeout_circle_member(target_circle_id, one_id, 0);
      elsif batch_action = 'kick' then
        perform public.kick_circle_member(target_circle_id, one_id);
      else
        for media_row in
          select b.bucket_id, b.object_path
          from public.ban_circle_member(
            target_circle_id,
            one_id,
            batch_reason,
            coalesce(delete_message_hours, 0),
            duration_seconds
          ) b
        loop
          media := media || jsonb_build_array(jsonb_build_object(
            'bucket_id', media_row.bucket_id,
            'object_path', media_row.object_path
          ));
        end loop;
      end if;
      done := done + 1;
      results := results || jsonb_build_array(
        jsonb_build_object('user_id', one_id, 'ok', true));
    exception when others then
      results := results || jsonb_build_array(jsonb_build_object(
        'user_id', one_id,
        'ok', false,
        'error', sqlerrm,
        'code', sqlstate
      ));
    end;
  end loop;

  perform public.write_circle_audit(
    target_circle_id,
    'member_batch_action',
    'circle',
    target_circle_id,
    (select c.name from public.circles c where c.id = target_circle_id),
    jsonb_build_object(
      'action', batch_action,
      'requested', cardinality(ids),
      'done', done
    )
  );

  return jsonb_build_object('results', results, 'media', media, 'done', done);
end;
$$;

revoke execute on function public.list_circle_members_for_moderation(
  uuid, integer, integer, integer, integer, integer, uuid, boolean, text, integer, integer
) from public, anon;
revoke execute on function public.batch_moderate_circle_members(
  uuid, uuid[], text, integer, text, integer
) from public, anon;
grant execute on function public.list_circle_members_for_moderation(
  uuid, integer, integer, integer, integer, integer, uuid, boolean, text, integer, integer
) to authenticated;
grant execute on function public.batch_moderate_circle_members(
  uuid, uuid[], text, integer, text, integer
) to authenticated;
