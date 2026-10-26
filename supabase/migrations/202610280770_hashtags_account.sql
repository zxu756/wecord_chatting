-- Topics and circle posts 2.0 (roadmap B8), part 8 of 8: leaving WeCord and
-- taking your data.
--
-- * Deleting an account (the profile gets a deleted_at). The tags of a
--   Moment live in the post (moments_posts.tags) and go with it when
--   Moments 2.0 erases the person's posts (202610260650), as do the circle
--   posts the person wrote when the account itself is removed (their title,
--   tags and featured mark are columns of the post). What is left
--   outside a post is the list of "your post was featured" pushes still
--   waiting: those of the person go at once (same pattern as
--   profiles_erase_events2, 202610270470), and a moderator's name is taken
--   off the ones they sent. prepare_account_deletion is not rewritten.
-- * export_my_circle_posts(user) is for the data-export Edge Function
--   (service role only, like export_my_group_space). The circle posts the
--   person wrote, and only those: the circle's name while they still belong,
--   the title, the text, the tags, whether it is featured and when, when it
--   was written, and the picture (bucket and path, which the function signs
--   into a link, and the description). Moments' topics need nothing new:
--   export_my_moments returns every column of the person's posts, `tags`
--   included.

create or replace function public.erase_featured_notices_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.circle_post_feature_notices n where n.user_id = new.id;
  update public.circle_post_feature_notices n
  set actor_id = null
  where n.actor_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_featured_notices_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_featured_notices on public.profiles;
create trigger profiles_erase_featured_notices
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_featured_notices_of_deleted_account();

create or replace function public.export_my_circle_posts(target_user_id uuid)
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
    'posts', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'circle', case when m.user_id is not null then c.name end,
          'title', p.title,
          'text', p.body,
          'tags', to_jsonb(p.tags),
          'featured', p.featured_at is not null,
          'featured_at', p.featured_at,
          'written_at', p.created_at,
          'bucket', p.attachment->>'bucket',
          'path', p.attachment->>'path',
          'description', nullif(p.attachment->>'alt', '')
        ))
        order by p.created_at desc, p.id
      )
      from (
        select * from public.circle_posts x
        where x.author_id = target_user_id
          and x.deleted_at is null
        order by x.created_at desc, x.id desc
        limit 2000
      ) p
      join public.circles c on c.id = p.circle_id
      left join public.circle_members m
        on m.circle_id = p.circle_id and m.user_id = target_user_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.export_my_circle_posts(uuid)
  from public, anon, authenticated;
grant execute on function public.export_my_circle_posts(uuid) to service_role;
