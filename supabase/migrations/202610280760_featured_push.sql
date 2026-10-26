-- Topics and circle posts 2.0 (roadmap B8), part 7 of 8: "your post was
-- featured".
--
-- When a moderator features someone else's post, the author gets a push once
-- (the same post never pushes twice, however often it is featured again).
-- The path is the one the Q&A pushes use (202610270310_qa_solved.sql):
--
--   * a trigger on circle_posts writes a row in circle_post_feature_notices
--     and wakes scheduled-dispatch (wake_scheduled_dispatch, 202610210430);
--     run_later_dispatch() and the cron jobs are not touched;
--   * claim_featured_post_pushes() is what scheduled-dispatch claims: one row
--     per device, worded in the device's language ('en' or 'zh'). A notice
--     older than 15 minutes when the function gets to it is closed without a
--     push. Nothing goes to a person who left the circle, deleted or lost
--     their account (K1 suspension), muted the circle or set its level to
--     none, or who is blocked with the moderator (either way), nor for a post
--     that was removed or un-featured meanwhile, nor in a suspended circle.
--     Quiet hours and Do Not Disturb (A4) hold it back in scheduled-dispatch
--     like every other push. The post is not a chat, so there is no chat to
--     lock (G2) and the words carry only the circle's name and the post's
--     title (a post without a title says "your post").
--   * the title and the circle's name are cleaned of angle brackets, so they
--     cannot pass for a time token in the text.

create table if not exists public.circle_post_feature_notices (
  post_id uuid primary key references public.circle_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  circle_id uuid not null references public.circles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  push_claimed_at timestamptz
);

create index if not exists circle_post_feature_notices_unclaimed_idx
  on public.circle_post_feature_notices (created_at)
  where push_claimed_at is null;

create index if not exists circle_post_feature_notices_user_idx
  on public.circle_post_feature_notices (user_id);

alter table public.circle_post_feature_notices enable row level security;
revoke all on public.circle_post_feature_notices from anon, authenticated;

create or replace function public.circle_posts_notify_featured()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted integer;
begin
  if new.featured_at is null
    or new.author_id = coalesce(new.featured_by, auth.uid())
    or public.is_user_suspended(new.author_id)
  then
    return new;
  end if;

  insert into public.circle_post_feature_notices (post_id, user_id, circle_id, actor_id)
  values (new.id, new.author_id, new.circle_id, coalesce(new.featured_by, auth.uid()))
  on conflict (post_id) do nothing;
  get diagnostics inserted = row_count;

  if inserted > 0 then
    perform public.wake_scheduled_dispatch();
  end if;
  return new;
end;
$$;

revoke execute on function public.circle_posts_notify_featured()
  from public, anon, authenticated;

drop trigger if exists circle_posts_notify_featured on public.circle_posts;
create trigger circle_posts_notify_featured
  after update of featured_at on public.circle_posts
  for each row
  when (old.featured_at is null and new.featured_at is not null)
  execute function public.circle_posts_notify_featured();

create or replace function public.claim_featured_post_pushes()
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
  -- Too old to be worth a push now.
  update public.circle_post_feature_notices n
  set push_claimed_at = now()
  where n.push_claimed_at is null
    and n.created_at <= now() - interval '15 minutes';

  return query
  with claimed as (
    update public.circle_post_feature_notices n
    set push_claimed_at = now()
    where n.push_claimed_at is null
    returning n.*
  ),
  named as (
    select
      c.post_id,
      c.user_id,
      c.circle_id,
      nullif(btrim(replace(replace(
        coalesce(cp.title, left(regexp_replace(cp.body, '\s+', ' ', 'g'), 40)),
        '<', ''), '>', '')), '') as post_title,
      btrim(replace(replace(ci.name, '<', ''), '>', '')) as circle_name
    from claimed c
    join public.circle_posts cp
      on cp.id = c.post_id
      and cp.deleted_at is null
      and cp.featured_at is not null
    join public.circles ci
      on ci.id = c.circle_id
      and ci.disabled_mode is distinct from 'suspend'
    join public.circle_members cm
      on cm.circle_id = c.circle_id and cm.user_id = c.user_id
    join public.profiles pr
      on pr.id = c.user_id and pr.deleted_at is null
    left join public.circle_notification_settings ns
      on ns.circle_id = c.circle_id and ns.user_id = c.user_id
    where not public.is_user_suspended(c.user_id)
      and (c.actor_id is null or not public.are_users_blocked(c.user_id, c.actor_id))
      and coalesce(ns.level, 'all') <> 'none'
      and (ns.muted_until is null or ns.muted_until < now())
  )
  select
    s.id,
    s.endpoint,
    s.p256dh,
    s.auth,
    null::uuid,
    null::uuid,
    case when s.language = 'zh' then '你的帖子被设为精华'
      else 'Your post was featured' end,
    case
      when s.language = 'zh' and d.post_title is not null then
        '「' || d.circle_name || '」的版主把你的帖子「' || d.post_title
          || '」设为了精华。'
      when s.language = 'zh' then
        '「' || d.circle_name || '」的版主把你的帖子设为了精华。'
      when d.post_title is not null then
        'A moderator featured your post "' || d.post_title || '" in '
          || d.circle_name || '.'
      else
        'A moderator featured your post in ' || d.circle_name || '.'
    end,
    'featured-' || d.post_id::text,
    '/#/circles/' || d.circle_id::text || '/posts/' || d.post_id::text
  from named d
  join public.push_subscriptions s on s.user_id = d.user_id;
end;
$$;

revoke execute on function public.claim_featured_post_pushes()
  from public, anon, authenticated;
grant execute on function public.claim_featured_post_pushes() to service_role;
