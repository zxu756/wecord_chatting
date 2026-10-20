-- Moments 2.0 (roadmap B2), part 4 of 6: the push for a reminder.
--
-- claim_moments_pushes (latest before this: 202610200010_push_text_language
-- .sql, which words each push per subscription language and falls back to
-- "某人" / "Someone"), the same function with:
--   * the 'mention' kind: "<name> reminded you to read their Moment" /
--     "<name> 提醒你看了Ta的朋友圈", with the start of the post as the body;
--     it passes the same checks as the other kinds (not in Do Not Disturb,
--     "Moments notifications" on, the post still visible to the person);
--   * a comment that is only a picture or sticker: its body says "[Picture]"
--     / "[图片]" instead of the start of the post.
-- Mentions are claimed by the same two callers: the author's app right after
-- posting (the push function, {moments_post_id}) and the scheduled dispatch
-- (run_later_dispatch already wakes it while a Moments notification waits).

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
        when 'mention' then ' 提醒你看TA的朋友圈'
        else ' 回复了你的评论'
      end
    else
      actor.name || case c.kind
        when 'like' then ' liked your Moment'
        when 'comment' then ' commented on your Moment'
        when 'mention' then ' reminded you to read their Moment'
        else ' replied to your comment'
      end
    end,
    case
      when c.kind in ('comment', 'reply') and btrim(c.snippet) <> ''
        then left(c.snippet, 200)
      when c.kind in ('comment', 'reply') and mc.image is not null
        then case when s.language = 'zh' then '[图片]' else '[Picture]' end
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
      case when s.language = 'zh' then '某人' else 'Someone' end
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
