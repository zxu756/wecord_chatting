-- Moments, live: a "something changed" signal, never the data.
--
-- Why not postgres_changes. Realtime would send the row itself to every
-- subscriber, after running the table's row level security for each of them.
-- moments_posts has column grants (the audience is secret), DELETE events
-- carry no policy check at all, and a like or comment is visible by the
-- mutual friends rule (moments_interaction_visible), not by a column the
-- subscription could filter on. So nothing here is published to
-- postgres_changes. Instead the database tells each person who may see a
-- change, on their own private broadcast channel, that "post X changed":
--
--   topic   moments:<user id>          (private channel)
--   event   post           a new post that person may see
--           post_removed   a post they could see is gone
--           reaction       a like or comment on a post (or its removal)
--                          that person may see
--   payload {"post_id": "<uuid>"}
--
-- The payload holds no text, no names and no counts. The app reacts by
-- reading again through the same RPCs as always (moments_feed,
-- moments_unseen_summary, list_moments_notifications), which apply every
-- visibility rule themselves, so a signal can never show more than the RPCs
-- would: the worst a wrong signal does is one wasted request.
--
-- Who is told, decided here when the change happens:
--   * post, post_removed: the author's friends for whom moments_post_visible_to
--     holds (audience, "Don't let them see", visible range, blocks).
--   * reaction: the poster and the poster's friends who can see the post and
--     for whom moments_interaction_visible holds (so a person who is not a
--     friend of the commenter is not even told), except the person who just
--     did it (their own app already reads the post back).
--
-- Who may listen: the policy on realtime.messages lets a signed-in person
-- receive broadcasts only on their own topic. Nobody can send (no insert
-- policy; the triggers write through realtime.send as the function owner).
-- A reconnecting app misses nothing important: it reads everything again
-- when the channel (re)subscribes.
--
-- Cost: one realtime.send per recipient per change (a friend list, in the
-- hundreds at most), in the same transaction. Failures in realtime are
-- swallowed: a post, like or comment must never fail because of the signal.

-- Only your own topic, only to receive.
drop policy if exists moments_signals_receive_own on realtime.messages;
create policy moments_signals_receive_own
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'moments:' || (select auth.uid())::text
  );

-- Sends one signal. Internal.
create or replace function public.moments_signal(
  recipient uuid,
  event_name text,
  target_post uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if recipient is null or target_post is null then
    return;
  end if;
  begin
    perform realtime.send(
      jsonb_build_object('post_id', target_post),
      event_name,
      'moments:' || recipient::text,
      true
    );
  exception when others then
    -- No Realtime here (or it is unwell): the signal is a courtesy.
    null;
  end;
end;
$$;

-- Everyone who may see post [p]: the author's friends for whom the
-- visibility rules hold. Internal.
create or replace function public.moments_post_audience(p public.moments_posts)
returns table (viewer_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select friend.id
  from (
    select case when f.user_low_id = p.author_id then f.user_high_id else f.user_low_id end as id
    from public.friendships f
    where p.author_id in (f.user_low_id, f.user_high_id)
  ) friend
  where public.moments_post_visible_to(friend.id, p);
$$;

create or replace function public.moments_signal_new_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer record;
begin
  if new.visibility = 'private' then
    return new;
  end if;
  for viewer in select a.viewer_id from public.moments_post_audience(new) a loop
    perform public.moments_signal(viewer.viewer_id, 'post', new.id);
  end loop;
  return new;
end;
$$;

create or replace function public.moments_signal_removed_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer record;
begin
  if old.visibility = 'private' then
    return old;
  end if;
  for viewer in select a.viewer_id from public.moments_post_audience(old) a loop
    perform public.moments_signal(viewer.viewer_id, 'post_removed', old.id);
  end loop;
  return old;
end;
$$;

-- A like or comment by [actor] (replying to [replied_to]) on [target_post]
-- appeared or went. Internal.
create or replace function public.moments_signal_reaction(
  target_post uuid,
  actor uuid,
  replied_to uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.moments_posts%rowtype;
  doer uuid := auth.uid();
  viewer record;
begin
  select * into p from public.moments_posts where id = target_post;
  if p.id is null then
    -- The post itself is going (a cascade): post_removed covers it.
    return;
  end if;
  for viewer in
    select p.author_id as viewer_id
    union
    select a.viewer_id from public.moments_post_audience(p) a
  loop
    if viewer.viewer_id is distinct from doer
      and public.moments_post_visible_to(viewer.viewer_id, p)
      and public.moments_interaction_visible(
        viewer.viewer_id, p.author_id, actor, replied_to
      )
    then
      perform public.moments_signal(viewer.viewer_id, 'reaction', p.id);
    end if;
  end loop;
end;
$$;

create or replace function public.moments_signal_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.moments_signal_reaction(old.post_id, old.user_id, null);
    return old;
  end if;
  perform public.moments_signal_reaction(new.post_id, new.user_id, null);
  return new;
end;
$$;

create or replace function public.moments_signal_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.moments_signal_reaction(
      old.post_id, old.author_id, old.reply_to_user_id
    );
    return old;
  end if;
  perform public.moments_signal_reaction(
    new.post_id, new.author_id, new.reply_to_user_id
  );
  return new;
end;
$$;

revoke execute on function public.moments_signal(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.moments_post_audience(public.moments_posts) from public, anon, authenticated;
revoke execute on function public.moments_signal_new_post() from public, anon, authenticated;
revoke execute on function public.moments_signal_removed_post() from public, anon, authenticated;
revoke execute on function public.moments_signal_reaction(uuid, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.moments_signal_like() from public, anon, authenticated;
revoke execute on function public.moments_signal_comment() from public, anon, authenticated;

drop trigger if exists moments_posts_signal_new on public.moments_posts;
create trigger moments_posts_signal_new
  after insert on public.moments_posts
  for each row execute function public.moments_signal_new_post();

drop trigger if exists moments_posts_signal_removed on public.moments_posts;
create trigger moments_posts_signal_removed
  before delete on public.moments_posts
  for each row execute function public.moments_signal_removed_post();

drop trigger if exists moments_likes_signal on public.moments_likes;
create trigger moments_likes_signal
  after insert or delete on public.moments_likes
  for each row execute function public.moments_signal_like();

drop trigger if exists moments_comments_signal on public.moments_comments;
create trigger moments_comments_signal
  after insert or delete on public.moments_comments
  for each row execute function public.moments_signal_comment();
