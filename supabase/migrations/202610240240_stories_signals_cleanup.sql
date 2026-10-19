-- Daily (B1), part 5 of 6: live signals, the end of a daily, account deletion.
--
-- Live: "something changed", never the data (like Moments, 202610190020).
--   topic   stories:<user id>          (private channel, listen only)
--   event   story            a new daily that person may see
--           story_removed    a daily they could see was taken down
--   payload {"story_id": "<uuid>"}
-- The app reads the tray (stories_tray) again; every visibility rule is
-- applied by that RPC, so a signal can never show more than it would.
-- A daily that simply ends sends nothing: the app drops it when the clock
-- says so, and the tray asks again when the app comes back.
--
-- The end of a daily. Reads stop at expires_at (story_visible_to). The purge
-- then deletes the row; a trigger queues the three files (story_media_cleanup)
-- and the expire-stories Edge Function removes them from Storage, because
-- Storage objects can only be removed through its API. This does not touch
-- run_later_dispatch(): it has jobs of its own.
--   * purge_expired_stories(batch)  deletes dailies past their end, except
--     those with an open report (kept at most 30 days past the end, so the
--     admins can look), and clears old report copies.
--   * claim_story_media / finish_story_media  hand the queue to the function.
--   * pg_cron: 'wecord-purge-expired-stories' every five minutes in SQL, and
--     'wecord-expire-story-files' every five minutes, which calls
--     wake_expire_stories(): that posts to the Edge Function with the Vault
--     secrets wecord_functions_url and wecord_dispatch_secret (the secret is
--     the bearer token, like scheduled-dispatch). Without pg_cron nothing is
--     scheduled and the functions can be called by any scheduler.
--
-- Account deletion. prepare_account_deletion (202610160017) keeps the profile
-- as "Deleted User", so the foreign keys never fire. A trigger on
-- profiles.deleted_at erases the person's dailies (their files are queued),
-- their views and reactions on other people's dailies, their close friends
-- and the lists they are on. The delete-account function also empties their
-- folder of the stories bucket.

-- --------------------------------------------------------------- signals

drop policy if exists stories_signals_receive_own on realtime.messages;
create policy stories_signals_receive_own
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) = 'stories:' || (select auth.uid())::text
  );

create or replace function public.story_signal(
  recipient uuid,
  event_name text,
  target_story uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if recipient is null or target_story is null then
    return;
  end if;
  begin
    perform realtime.send(
      jsonb_build_object('story_id', target_story),
      event_name,
      'stories:' || recipient::text,
      true
    );
  exception when others then
    -- No Realtime here (or it is unwell): the signal is a courtesy.
    null;
  end;
end;
$$;

-- Everyone who may see daily [s]: the author's friends for whom the rule
-- holds. Internal.
create or replace function public.story_audience(s public.stories)
returns table (viewer_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select friend.id
  from (
    select case when f.user_low_id = s.author_id then f.user_high_id else f.user_low_id end as id
    from public.friendships f
    where s.author_id in (f.user_low_id, f.user_high_id)
  ) friend
  where public.story_visible_to(s, friend.id);
$$;

create or replace function public.story_signal_new()
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
  for viewer in select a.viewer_id from public.story_audience(new) a loop
    perform public.story_signal(viewer.viewer_id, 'story', new.id);
  end loop;
  return new;
end;
$$;

-- Taken down early (the author deleted it, an admin removed it). The end of
-- a daily by the clock is not announced.
create or replace function public.story_signal_removed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer record;
begin
  if old.visibility = 'private' or old.expires_at <= now() then
    return old;
  end if;
  for viewer in select a.viewer_id from public.story_audience(old) a loop
    perform public.story_signal(viewer.viewer_id, 'story_removed', old.id);
  end loop;
  return old;
end;
$$;

revoke execute on function public.story_signal(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.story_audience(public.stories) from public, anon, authenticated;
revoke execute on function public.story_signal_new() from public, anon, authenticated;
revoke execute on function public.story_signal_removed() from public, anon, authenticated;

drop trigger if exists stories_signal_new on public.stories;
create trigger stories_signal_new
  after insert on public.stories
  for each row execute function public.story_signal_new();

drop trigger if exists stories_signal_removed on public.stories;
create trigger stories_signal_removed
  after delete on public.stories
  for each row execute function public.story_signal_removed();

-- ------------------------------------------------------ files to remove

create or replace function public.stories_queue_files()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.story_media_cleanup (bucket_id, object_path)
  select 'stories', p.path
  from unnest(array[old.media_path, old.poster_path, old.thumb_path]) as p(path)
  where p.path is not null
  on conflict do nothing;
  return old;
end;
$$;

revoke execute on function public.stories_queue_files() from public, anon, authenticated;

drop trigger if exists stories_queue_files on public.stories;
create trigger stories_queue_files
  after delete on public.stories
  for each row execute function public.stories_queue_files();

-- Deletes the dailies past their end (those with an open report stay, up to
-- 30 days past the end) and clears old report copies. Returns how many.
create or replace function public.purge_expired_stories(batch_limit integer default 1000)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  with doomed as (
    select s.id
    from public.stories s
    where s.expires_at <= now()
      and (
        s.expires_at <= now() - interval '30 days'
        or not exists (
          select 1
          from public.story_reports r
          where r.story_id = s.id and r.status = 'open'
        )
      )
    order by s.expires_at
    limit greatest(1, least(coalesce(batch_limit, 1000), 5000))
  )
  delete from public.stories s
  using doomed
  where s.id = doomed.id;
  get diagnostics deleted_count = row_count;
  perform public.purge_old_story_report_data();
  return deleted_count;
end;
$$;

-- The queued files, for expire-stories to remove from Storage.
create or replace function public.claim_story_media(max_rows integer default 200)
returns table (bucket_id text, object_path text)
language sql
security definer
set search_path = public
as $$
  select c.bucket_id, c.object_path
  from public.story_media_cleanup c
  order by c.created_at, c.object_path
  limit greatest(1, least(coalesce(max_rows, 200), 1000));
$$;

create or replace function public.finish_story_media(paths text[])
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.story_media_cleanup c
  where c.bucket_id = 'stories'
    and c.object_path = any (coalesce(paths, '{}'));
$$;

revoke execute on function public.purge_expired_stories(integer) from public, anon, authenticated;
revoke execute on function public.claim_story_media(integer) from public, anon, authenticated;
revoke execute on function public.finish_story_media(text[]) from public, anon, authenticated;
grant execute on function public.purge_expired_stories(integer) to service_role;
grant execute on function public.claim_story_media(integer) to service_role;
grant execute on function public.finish_story_media(text[]) to service_role;

-- Wakes the expire-stories function the way the rest of the project wakes its
-- functions (wake_scheduled_dispatch, 202610210430): with the Vault secrets
-- wecord_functions_url and wecord_dispatch_secret, the secret as the bearer
-- token. Quietly does nothing where Vault or pg_net, or a secret, is missing.
create or replace function public.wake_expire_stories()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  functions_url text;
  dispatch_secret text;
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
    url := rtrim(functions_url, '/') || '/expire-stories',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || dispatch_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
exception when others then
  null;
end;
$$;

revoke execute on function public.wake_expire_stories() from public, anon, authenticated;
grant execute on function public.wake_expire_stories() to service_role;

-- Scheduling, only where pg_cron can be used. Reads skip ended dailies either
-- way, so a project without it still hides them at once. Both jobs are always
-- created; the secrets are checked when the job runs.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname in (
      'wecord-purge-expired-stories',
      'wecord-expire-story-files'
    );
    perform cron.schedule(
      'wecord-purge-expired-stories',
      '*/5 * * * *',
      'select public.purge_expired_stories(1000)'
    );
    perform cron.schedule(
      'wecord-expire-story-files',
      '*/5 * * * *',
      'select public.wake_expire_stories()'
    );
  else
    raise notice 'pg_cron is not available: call purge_expired_stories() and wake_expire_stories() from another scheduler';
  end if;
exception when others then
  raise notice 'Could not schedule the daily jobs with pg_cron: %', sqlerrm;
end;
$$;

-- ------------------------------------------------------ account deletion

create or replace function public.erase_stories_of_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Their dailies (the files are queued by the delete trigger) and with them
  -- the views and reactions on those.
  delete from public.stories s where s.author_id = new.id;
  -- What they viewed or reacted to on other people's dailies.
  delete from public.story_views v where v.viewer_id = new.id;
  delete from public.story_reactions r where r.user_id = new.id;
  delete from public.story_close_friends cf
  where cf.owner_id = new.id or cf.friend_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_stories_of_deleted_account()
  from public, anon, authenticated;

drop trigger if exists profiles_erase_stories on public.profiles;
create trigger profiles_erase_stories
  after update of deleted_at on public.profiles
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_stories_of_deleted_account();
