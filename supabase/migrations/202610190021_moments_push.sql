-- Moments push: likes, comments and replies on MY posts and comments reach
-- my devices as web push. New posts do not (as in WeChat: they show as a
-- dot on the Moments entry, not as a notification).
--
-- The notifications themselves are made by the triggers of
-- 202610180041_moments.sql (moments_notifications). This adds the push:
--
-- * moments_notifications.pushed_at, set when the push was claimed, so each
--   notification is pushed at most once, whoever asks first.
-- * claim_moments_pushes(caller_id, target_post_id), service role only, the
--   same kind of claim function as claim_push_delivery:
--     - the actor's app asks right after a like or comment (the push Edge
--       Function, {moments_post_id}; caller_id is the actor, so nobody can
--       claim someone else's notifications), and
--     - the scheduled-dispatch tick sweeps what is still unclaimed
--       (caller_id null), so a push is not lost when the actor's app was
--       closed before it asked. run_later_dispatch wakes the function while
--       a fresh notification waits.
--   Only notifications of the last 10 minutes are sent; older unclaimed ones
--   are closed without a push, so a long outage does not end in a burst.
-- * Each push goes to every subscription of the recipient, written in the
--   subscription's language ('en' or 'zh'; the Edge Functions write any time
--   token for the subscription's time zone), and tagged per post so several
--   likes of one post replace each other.
--
-- Who is NOT pushed (the notification still waits in the inbox):
--   * someone in Do Not Disturb (user_privacy_settings.presence_status);
--   * someone who turned "Moments notifications" off (moments_settings
--     .push_enabled, Settings -> Moments);
--   * someone who cannot see it any more. The claim re-checks, at the moment
--     of the push, the same two rules as list_moments_notifications: the
--     post is visible to the recipient (moments_post_visible_to) and the
--     reaction passes the mutual friends rule (moments_interaction_visible),
--     so a comment by a stranger-of-mine on a friend's post is never pushed
--     to me, and unfriending or blocking before the push cancels it.
-- The push shows the actor's name as the recipient knows them (their alias
-- wins) and, for a comment, its text; for a like, the start of the post.

alter table public.moments_notifications
  add column if not exists pushed_at timestamptz;

-- What exists already has long been seen (or not) in the inbox: never push it.
update public.moments_notifications
set pushed_at = created_at
where pushed_at is null;

create index if not exists moments_notifications_unpushed_idx
  on public.moments_notifications (created_at)
  where pushed_at is null;

alter table public.moments_settings
  add column if not exists push_enabled boolean not null default true;

-- 202610180041 plus [p_push_enabled] (Settings -> Moments -> notifications).
-- The old three argument version goes: the new one takes the same call.
drop function if exists public.set_moments_settings(text, text, boolean);

create or replace function public.set_moments_settings(
  p_visible_range text default null,
  p_cover_path text default null,
  p_clear_cover boolean default false,
  p_push_enabled boolean default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  previous_cover text;
begin
  if me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_visible_range is not null
    and p_visible_range not in ('all', 'six_months', 'one_month', 'three_days')
  then
    raise exception 'Unknown range' using errcode = '22023';
  end if;
  insert into public.moments_settings (user_id) values (me)
  on conflict (user_id) do nothing;
  select cover_path into previous_cover from public.moments_settings where user_id = me;
  update public.moments_settings
  set visible_range = coalesce(p_visible_range, visible_range),
      cover_path = case
        when p_clear_cover then null
        else coalesce(p_cover_path, cover_path)
      end,
      push_enabled = coalesce(p_push_enabled, push_enabled),
      updated_at = now()
  where user_id = me;
  if previous_cover is not null
    and previous_cover is distinct from (
      select cover_path from public.moments_settings where user_id = me
    )
  then
    return previous_cover;
  end if;
  return null;
end;
$$;

revoke execute on function public.set_moments_settings(text, text, boolean, boolean) from public, anon;
grant execute on function public.set_moments_settings(text, text, boolean, boolean) to authenticated;

-- Claims the Moments pushes to send. Service role only.
create or replace function public.claim_moments_pushes(
  caller_id uuid default null,
  target_post_id uuid default null
)
returns table (
  subscription_id uuid,
  endpoint text,
  p256dh text,
  auth text,
  conversation_id uuid,
  circle_id uuid,
  title text,
  body text,
  tag text,
  url text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  -- Too old to be news: closed without a push.
  update public.moments_notifications n
  set pushed_at = now()
  where n.pushed_at is null
    and n.created_at <= now() - interval '10 minutes';

  return query
  with claimed as (
    update public.moments_notifications n
    set pushed_at = now()
    where n.pushed_at is null
      and n.created_at > now() - interval '10 minutes'
      and (caller_id is null or n.actor_id = caller_id)
      and (target_post_id is null or n.post_id = target_post_id)
    returning n.*
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then
      actor.name || case c.kind
        when 'like' then ' 赞了你的朋友圈'
        when 'comment' then ' 评论了你的朋友圈'
        else ' 回复了你的评论'
      end
    else
      actor.name || case c.kind
        when 'like' then ' liked your Moment'
        when 'comment' then ' commented on your Moment'
        else ' replied to your comment'
      end
    end,
    case
      when c.kind <> 'like' and btrim(c.snippet) <> '' then left(c.snippet, 200)
      when nullif(btrim(p.body), '') is not null then left(btrim(p.body), 80)
      when s.language = 'zh' then case p.kind
        when 'photos' then '[图片]'
        when 'video' then '[视频]'
        when 'link' then coalesce(p.link_title, p.link_url, '[链接]')
        else ''
      end
      else case p.kind
        when 'photos' then '[Photo]'
        when 'video' then '[Video]'
        when 'link' then coalesce(p.link_title, p.link_url, '[Link]')
        else ''
      end
    end,
    'moments-' || c.post_id::text,
    '/#/moments/' || c.post_id::text
  from claimed c
  join public.moments_posts p on p.id = c.post_id
  left join public.moments_comments mc on mc.id = c.comment_id
  join public.push_subscriptions s on s.user_id = c.user_id
  join lateral (
    select coalesce(
      nullif(btrim(ca.alias), ''),
      nullif(btrim(pr.display_name), ''),
      pr.username,
      'Someone'
    ) as name
    from public.profiles pr
    left join public.contact_aliases ca
      on ca.owner_id = c.user_id and ca.friend_id = pr.id
    where pr.id = c.actor_id
  ) actor on true
  left join public.user_privacy_settings ups on ups.user_id = c.user_id
  left join public.moments_settings ms on ms.user_id = c.user_id
  where coalesce(ups.presence_status, 'online') <> 'dnd'
    and coalesce(ms.push_enabled, true)
    -- Still visible to the recipient, by the rules of the inbox.
    and public.moments_post_visible_to(c.user_id, p)
    and public.moments_interaction_visible(
      c.user_id, p.author_id, c.actor_id, mc.reply_to_user_id
    );
end;
$$;

revoke execute on function public.claim_moments_pushes(uuid, uuid) from public, anon, authenticated;
grant execute on function public.claim_moments_pushes(uuid, uuid) to service_role;

-- 202610170070 with one more reason to wake scheduled-dispatch: a Moments
-- notification nobody has pushed yet.
create or replace function public.run_later_dispatch()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pushes_waiting boolean;
  functions_url text;
  dispatch_secret text;
begin
  perform public.dispatch_due_scheduled_messages();
  perform public.chat_event_due_reminders();

  -- Dismissed reminders go after a month.
  delete from public.message_reminders r
  where r.dismissed_at < now() - interval '30 days';

  select exists (
    select 1
    from public.scheduled_messages s
    where s.status = 'sent'
      and s.push_claimed_at is null
      and s.sent_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.message_reminders r
    where r.push_claimed_at is null
      and r.dismissed_at is null
      and r.remind_at <= now()
      and r.remind_at > now() - interval '15 minutes'
  ) or exists (
    select 1
    from public.chat_event_reminders r
    where r.push_sent_at is null
      and r.created_at > now() - interval '30 minutes'
  ) or exists (
    -- The same items due_list_item_reminders() looks at, for a member who
    -- has no notice of this kind for this due date yet.
    select 1
    from public.task_items i
    join public.task_lists l on l.id = i.list_id and l.deleted_at is null
    left join public.task_item_assignees a on a.item_id = i.id
    join public.conversation_members cm
      on cm.conversation_id = l.conversation_id
      and cm.user_id = coalesce(a.user_id, i.created_by)
    where i.deleted_at is null
      and i.completed_at is null
      and i.due_at is not null
      and i.due_at > now() - interval '2 days'
      and i.due_at <= now() + case
        when i.due_has_time then interval '1 hour'
        else interval '12 hours'
      end
      and not exists (
        select 1
        from public.task_notifications n
        where n.user_id = cm.user_id
          and n.item_id = i.id
          and n.due_at = i.due_at
          and n.kind = case when i.due_at < now() then 'overdue' else 'due_soon' end
      )
  ) or exists (
    select 1
    from public.recalled_message_media r
    where r.expired
  ) or exists (
    -- A like, comment or reply on a Moment whose push nobody has claimed
    -- (claim_moments_pushes).
    select 1
    from public.moments_notifications mn
    where mn.pushed_at is null
      and mn.created_at > now() - interval '10 minutes'
  )
  into pushes_waiting;

  if not pushes_waiting then
    return;
  end if;

  begin
    select d.decrypted_secret
    into functions_url
    from vault.decrypted_secrets d
    where d.name = 'wecord_functions_url';
    select d.decrypted_secret
    into dispatch_secret
    from vault.decrypted_secrets d
    where d.name = 'wecord_dispatch_secret';

    if functions_url is null or dispatch_secret is null then
      return;
    end if;

    perform net.http_post(
      url := rtrim(functions_url, '/') || '/scheduled-dispatch',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || dispatch_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    );
  exception when others then
    -- No Vault or pg_net here: the work is done, only the push waits.
    null;
  end;
end;
$$;

revoke execute on function public.run_later_dispatch() from public, anon, authenticated;
grant execute on function public.run_later_dispatch() to service_role;
