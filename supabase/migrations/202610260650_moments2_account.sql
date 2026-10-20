-- Moments 2.0 (roadmap B2), part 6 of 6: deleting an account and taking your
-- data.
--
-- * Deleting an account. prepare_account_deletion (202610160026) leaves the
--   profile as "Deleted User" with deleted_at set, so what hung on the
--   profile has to go in a trigger, as stories (202610240240) and favorites
--   (202610250400) do it: when deleted_at is set, the person's Moments go
--   (posts with their likes, comments and notifications, the comments and
--   likes they left elsewhere, their settings, their pins and the reminders
--   they sent), and they are taken out of other people's "Remind who to read"
--   lists. The files (including comment pictures, which sit in their own
--   folder of the moments bucket) are removed by the delete-account function,
--   which empties that folder.
-- * Download my data. export_my_moments (202610190023) already carries every
--   column of my posts, so pinned_at, the pictures' descriptions and the ids
--   of the people I reminded are in it. export_my_moments_more(user) adds the
--   rest, for the data-export Edge Function (service role only):
--     pinned           my pinned posts, by when they were pinned
--     reminded         for each of my posts, the people I reminded (named)
--     reminded_by      posts that reminded me: who, when (never their words)
--     comment_pictures the pictures on the comments I wrote: the file in the
--                      moments bucket, its description, the post and when
--   Other people's posts and pictures are never read.

create or replace function public.erase_moments_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Their posts, and with them the likes, comments and notices on those.
  delete from public.moments_posts p where p.author_id = new.id;
  -- What they left on other people's posts.
  delete from public.moments_comments c where c.author_id = new.id;
  delete from public.moments_likes l where l.user_id = new.id;
  delete from public.moments_notifications n
  where n.user_id = new.id or n.actor_id = new.id;
  delete from public.moments_friend_prefs fp
  where fp.owner_id = new.id or fp.friend_id = new.id;
  delete from public.moments_settings s where s.user_id = new.id;
  -- Other people's reminders no longer name them.
  update public.moments_posts p
  set mentioned_user_ids = array_remove(p.mentioned_user_ids, new.id)
  where new.id = any (p.mentioned_user_ids);
  return new;
end;
$$;

revoke execute on function public.erase_moments_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_moments on public.profiles;
create trigger profiles_erase_moments
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_moments_of_deleted_account();

create or replace function public.export_my_moments_more(target_user_id uuid)
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
    'pinned', coalesce((
      select jsonb_agg(
        jsonb_build_object('post_id', p.id, 'pinned_at', p.pinned_at)
        order by p.pinned_at desc, p.id
      )
      from public.moments_posts p
      where p.author_id = target_user_id and p.pinned_at is not null
    ), '[]'::jsonb),
    'reminded', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'post_id', r.id,
          'created_at', r.created_at,
          'people', (
            select jsonb_agg(public.export_person_json(m.id) order by m.id)
            from unnest(r.mentioned_user_ids) as m(id)
          )
        )
        order by r.created_at desc, r.id
      )
      from (
        select p.id, p.created_at, p.mentioned_user_ids
        from public.moments_posts p
        where p.author_id = target_user_id
          and cardinality(p.mentioned_user_ids) > 0
        order by p.created_at desc, p.id desc
        limit 5000
      ) r
    ), '[]'::jsonb),
    'reminded_by', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'post_id', r.id,
          'from', public.export_person_json(r.author_id),
          'created_at', r.created_at
        )
        order by r.created_at desc, r.id
      )
      from (
        select p.id, p.author_id, p.created_at
        from public.moments_posts p
        where target_user_id = any (p.mentioned_user_ids)
        order by p.created_at desc, p.id desc
        limit 5000
      ) r
    ), '[]'::jsonb),
    'comment_pictures', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'comment_id', c.id,
          'post_id', c.post_id,
          'bucket', 'moments',
          'path', c.image->>'path',
          'description', c.image->>'alt',
          'created_at', c.created_at
        )
        order by c.created_at desc, c.id
      )
      from (
        select mc.id, mc.post_id, mc.image, mc.created_at
        from public.moments_comments mc
        where mc.author_id = target_user_id and mc.image is not null
        order by mc.created_at desc, mc.id desc
        limit 5000
      ) c
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_moments_more(uuid) from public;
revoke execute on function public.export_my_moments_more(uuid) from anon;
revoke execute on function public.export_my_moments_more(uuid) from authenticated;
