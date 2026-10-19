-- Moderator tools 2.0 (C5), part 1 of 9: bans that end.
--
-- circle_bans gains expires_at. A ban with no expiry is permanent, as before.
-- A ban with one lifts itself:
--
--   * run_circle_safety_sweep (pg_cron, every minute; its own job, so
--     run_later_dispatch is left alone) calls expire_circle_bans, which
--     deletes the ended bans and writes a member_unban_auto entry to the
--     circle's audit log (no actor: the clock did it);
--   * circle_members_reject_banned (the BEFORE INSERT guard on every join
--     path) ignores an ended ban and deletes it on the spot, so somebody
--     whose ban ran out seconds ago is not turned away until the next sweep.
--     The Discover and request paths, which read circle_bans directly, can
--     still see an ended ban for up to a minute.
--
-- ban_circle_member takes a duration (ban_duration_seconds; null or 0 =
-- permanent). It is rewritten from its newest definition, 202610140007 (the
-- chat-files bucket in the media clean-up is kept; only the duration and the
-- take-down check are new). The four-argument calls of old (the report
-- queue's "ban" decision) keep working: the new argument has a default.
-- Rank and permission rules are as they were: ban_members, and nobody ranked
-- at or above the caller, nor the owner, can be banned.

alter table public.circle_bans
  add column if not exists expires_at timestamptz;

alter table public.circle_bans
  drop constraint if exists circle_bans_expiry_after_start;
alter table public.circle_bans
  add constraint circle_bans_expiry_after_start
  check (expires_at is null or expires_at > created_at);

create index if not exists circle_bans_expires_idx
  on public.circle_bans (expires_at)
  where expires_at is not null;

-- Refuses the circle's moderation actions while a platform admin has the
-- circle down (K1, delisted or suspended).
create or replace function public.assert_circle_up(target_circle_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.disabled_at is not null
  ) then
    raise exception 'This circle is not available' using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.assert_circle_up(uuid)
  from public, anon, authenticated;

-- 202610140004's guard, ignoring (and clearing) a ban that has ended.
create or replace function public.reject_banned_circle_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_bans b
  where b.circle_id = new.circle_id
    and b.user_id = new.user_id
    and b.expires_at is not null
    and b.expires_at <= now();

  if exists (
    select 1
    from public.circle_bans b
    where b.circle_id = new.circle_id
      and b.user_id = new.user_id
  ) then
    raise exception 'Banned from this circle' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.reject_banned_circle_member() from public;

-- Lifts every ban that has ended. Returns how many.
create or replace function public.expire_circle_bans()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  lifted record;
  total integer := 0;
begin
  for lifted in
    with ended as (
      delete from public.circle_bans b
      where b.expires_at is not null
        and b.expires_at <= now()
      returning b.circle_id, b.user_id, b.expires_at
    )
    select * from ended
  loop
    total := total + 1;
    insert into public.circle_audit_log (
      circle_id, actor_id, action, target_type, target_id, target_label, changes
    )
    values (
      lifted.circle_id,
      null,
      'member_unban_auto',
      'member',
      lifted.user_id,
      public.circle_member_label(lifted.circle_id, lifted.user_id),
      jsonb_build_object('expired_at', lifted.expires_at)
    );
  end loop;
  return total;
end;
$$;

revoke execute on function public.expire_circle_bans()
  from public, anon, authenticated;
grant execute on function public.expire_circle_bans() to service_role;

-- ---------------------------------------------------------------------------
-- ban_circle_member: 202610140007 plus a duration and the take-down check
-- ---------------------------------------------------------------------------

drop function if exists public.ban_circle_member(uuid, uuid, text, integer);

create or replace function public.ban_circle_member(
  target_circle_id uuid,
  target_user_id uuid,
  ban_reason text default null,
  delete_message_hours integer default 0,
  ban_duration_seconds integer default null
)
returns table (bucket_id text, object_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_reason text := nullif(btrim(coalesce(ban_reason, '')), '');
  is_member boolean;
  banned_label text;
  deleted_count integer := 0;
  target public.messages%rowtype;
  media_bucket text;
  media_path text;
  ends_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'ban_members'
  ) then
    raise exception 'Only members who can ban members can ban members'
      using errcode = '42501';
  end if;

  perform public.assert_circle_up(target_circle_id);

  if trimmed_reason is not null and char_length(trimmed_reason) > 512 then
    raise exception 'Ban reason is too long' using errcode = '22023';
  end if;

  if coalesce(delete_message_hours, 0) not between 0 and 168 then
    raise exception 'Messages can be deleted from up to 7 days back'
      using errcode = '22023';
  end if;

  -- null or 0: permanent. Otherwise a minute to a year.
  if coalesce(ban_duration_seconds, 0) <> 0
    and ban_duration_seconds not between 60 and 31536000
  then
    raise exception 'A ban lasts from a minute to a year, or until lifted'
      using errcode = '22023';
  end if;
  ends_at := case
    when coalesce(ban_duration_seconds, 0) = 0 then null
    else now() + make_interval(secs => ban_duration_seconds)
  end;

  -- Serialises with role changes, so the rank check below holds.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_user_id = current_user_id then
    raise exception 'You cannot ban yourself' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = target_user_id) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.circles c
    where c.id = target_circle_id
      and c.owner_id = target_user_id
  ) then
    raise exception 'The circle owner cannot be banned' using errcode = '42501';
  end if;

  is_member := exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  );

  if is_member
    and public.circle_member_rank(target_circle_id, target_user_id)
      >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot ban a member ranked at or above you'
      using errcode = '42501';
  end if;

  banned_label := public.circle_member_label(target_circle_id, target_user_id);

  -- clock_timestamp, not now(): a ban is told apart from the one before it by
  -- its time (appeals are one per ban), also within one transaction.
  insert into public.circle_bans (
    circle_id, user_id, reason, banned_by, expires_at, created_at
  )
  values (
    target_circle_id, target_user_id, trimmed_reason, current_user_id, ends_at,
    clock_timestamp()
  )
  on conflict (circle_id, user_id) do update
  set
    reason = excluded.reason,
    banned_by = excluded.banned_by,
    expires_at = excluded.expires_at,
    created_at = excluded.created_at;

  if is_member then
    perform public.remove_circle_member_rows(target_circle_id, target_user_id);
  end if;

  if coalesce(delete_message_hours, 0) > 0 then
    for target in
      select m.*
      from public.messages m
      where m.sender_id = target_user_id
        and m.webhook_id is null
        and m.recalled_at is null
        and m.type <> 'system'
        and m.created_at >= now() - make_interval(hours => delete_message_hours)
        and m.conversation_id in (
          select cc.conversation_id
          from public.circle_channels cc
          where cc.circle_id = target_circle_id
          union all
          select ct.conversation_id
          from public.conversation_threads ct
          join public.circle_channels cc
            on cc.conversation_id = ct.parent_conversation_id
          where cc.circle_id = target_circle_id
        )
      for update of m
    loop
      deleted_count := deleted_count + 1;
      media_bucket := target.attachment->>'bucket';
      media_path := target.attachment->>'path';
      if media_bucket is null
        or media_bucket not in ('chat-images', 'voice-messages', 'chat-files')
        or media_path is null
      then
        media_bucket := null;
        media_path := null;
      end if;

      update public.messages m
      set
        recalled_at = now(),
        recalled_by = current_user_id,
        body = '',
        attachment = null,
        reply_preview = null,
        forwarded_from = null,
        mentions = '[]'::jsonb
      where m.id = target.id;

      delete from public.message_mentions mm where mm.message_id = target.id;
      delete from public.message_reactions r where r.message_id = target.id;
      delete from public.message_poll_votes v where v.message_id = target.id;
      delete from public.pinned_messages p where p.message_id = target.id;

      update public.messages m
      set reply_preview = m.reply_preview || jsonb_build_object('body', '')
      where m.reply_to_message_id = target.id
        and jsonb_typeof(m.reply_preview) = 'object';

      if media_path is not null then
        insert into public.recalled_message_media (
          bucket_id,
          object_path,
          message_id,
          deleted_by
        )
        values (media_bucket, media_path, target.id, current_user_id)
        on conflict on constraint recalled_message_media_pkey do update
        set
          message_id = excluded.message_id,
          deleted_by = excluded.deleted_by,
          created_at = now();

        if not exists (
          select 1
          from public.messages m
          where m.attachment->>'path' = media_path
            and m.attachment->>'bucket' = media_bucket
        ) then
          bucket_id := media_bucket;
          object_path := media_path;
          return next;
        end if;
      end if;
    end loop;
  end if;

  perform public.write_circle_audit(
    target_circle_id,
    'member_ban',
    'member',
    target_user_id,
    banned_label,
    jsonb_strip_nulls(jsonb_build_object(
      'reason', trimmed_reason,
      'deleted_messages', nullif(deleted_count, 0),
      'until', ends_at
    ))
  );
end;
$$;

revoke execute on function public.ban_circle_member(uuid, uuid, text, integer, integer)
  from public, anon;
grant execute on function public.ban_circle_member(uuid, uuid, text, integer, integer)
  to authenticated;
