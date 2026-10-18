-- The door of the calendar-feed Edge Function (service role only).
--
-- calendar_feed_items(p_token_hash, p_from, p_to) checks a token's hash,
-- counts the request against the token's rate limit and, when all is well,
-- returns the person's events and tasks (kinds chat_event, circle_event and
-- task of My agenda; reminders and scheduled messages are private and never
-- leave the app) together with the feed options:
--
--   {"status": "ok", "include_content": false, "utc_offset_minutes": 480,
--    "language": "zh", "items": [ ... ]}
--   {"status": "invalid"}                       unknown token, or the person
--                                               is gone
--   {"status": "limited", "retry_after": 1800}  too many requests
--
-- The limit is 30 requests an hour per link: calendar apps ask every few
-- hours, so only a loop or a leaked link gets near it. A refused request is
-- not counted again.

create or replace function public.calendar_feed_items(
  p_token_hash text,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  feed public.calendar_feed_tokens%rowtype;
  allowed constant integer := 30;
  window_length constant interval := interval '1 hour';
  items jsonb;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('status', 'invalid');
  end if;

  select t.* into feed
  from public.calendar_feed_tokens t
  where t.token_hash = p_token_hash
  for update;

  if feed.user_id is null
    or exists (
      select 1 from public.profiles p
      where p.id = feed.user_id and p.deleted_at is not null
    )
  then
    return jsonb_build_object('status', 'invalid');
  end if;

  if now() - feed.window_started_at >= window_length then
    feed.window_started_at := now();
    feed.window_count := 0;
  end if;

  if feed.window_count >= allowed then
    update public.calendar_feed_tokens t
    set window_started_at = feed.window_started_at,
        window_count = feed.window_count
    where t.user_id = feed.user_id;
    return jsonb_build_object(
      'status', 'limited',
      'retry_after',
      greatest(
        1,
        ceil(extract(epoch from feed.window_started_at + window_length - now()))::integer
      )
    );
  end if;

  update public.calendar_feed_tokens t
  set window_started_at = feed.window_started_at,
      window_count = feed.window_count + 1,
      last_used_at = now()
  where t.user_id = feed.user_id;

  select coalesce(jsonb_agg(to_jsonb(a) order by a.starts_at, a.kind, a.target_id), '[]'::jsonb)
  into items
  from public.agenda_items_for_user(
    feed.user_id,
    p_from,
    p_to,
    array['chat_event', 'circle_event', 'task']
  ) as a;

  return jsonb_build_object(
    'status', 'ok',
    'include_content', feed.include_content,
    'utc_offset_minutes', feed.utc_offset_minutes,
    'language', feed.language,
    'items', items
  );
end;
$$;

revoke execute on function public.calendar_feed_items(text, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.calendar_feed_items(text, timestamptz, timestamptz)
  to service_role;
