-- Calendar subscription: the secret link of "My agenda".
--
-- A person makes a link in Settings and gives it to Apple Calendar or Google
-- Calendar, which cannot sign in. The link is
--
--   <functions url>/calendar-feed/<token>.ics
--
-- * calendar_feed_tokens keeps ONE row per person: the SHA-256 of the token
--   (never the token), whether the feed may show titles and descriptions
--   (off by default: the feed then holds only times and conversation names),
--   the person's UTC offset and language (the feed has no signed-in client to
--   ask: all-day tasks need the offset, labels need the language) and the
--   counters of the rate limit. The token is 192 random bits written in hex,
--   so it holds no user id and cannot be guessed.
-- * Nobody reads the table: it has no policy and no grant. The functions
--   below are the only way in, and they act on the caller's own row.
-- * create_calendar_feed_token makes a new token and returns it ONCE; the
--   server cannot show it again. Calling it again resets the link: the old
--   token stops working at once.
-- * get_calendar_feed_settings tells the app whether a link exists, whether
--   it shows content, when it was made and last used.
-- * set_calendar_feed_options changes the content switch, offset and language
--   without changing the token.
-- * delete_calendar_feed_token turns the subscription off.
-- * calendar_feed_items (next migration) is the service-role door of the
--   calendar-feed Edge Function.

create table if not exists public.calendar_feed_tokens (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  token_hash text not null,
  include_content boolean not null default false,
  utc_offset_minutes integer not null default 0,
  language text not null default 'en',
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  -- The rate limit: requests counted since window_started_at.
  window_started_at timestamptz not null default now(),
  window_count integer not null default 0,
  constraint calendar_feed_tokens_hash check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint calendar_feed_tokens_offset
    check (utc_offset_minutes between -840 and 840),
  constraint calendar_feed_tokens_language check (language in ('en', 'zh'))
);

create unique index if not exists calendar_feed_tokens_hash_idx
  on public.calendar_feed_tokens (token_hash);

alter table public.calendar_feed_tokens enable row level security;
revoke all on public.calendar_feed_tokens from anon, authenticated;

create or replace function public.calendar_feed_clean_language(p_language text)
returns text
language sql
immutable
as $$
  select case when lower(coalesce(p_language, '')) like 'zh%' then 'zh' else 'en' end;
$$;

revoke execute on function public.calendar_feed_clean_language(text) from public, anon, authenticated;

-- Makes (or resets) the caller's link and returns the token, once.
create or replace function public.create_calendar_feed_token(
  p_include_content boolean default false,
  p_utc_offset_minutes integer default 0,
  p_language text default 'en'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  new_token text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  new_token := encode(extensions.gen_random_bytes(24), 'hex');

  insert into public.calendar_feed_tokens (
    user_id, token_hash, include_content, utc_offset_minutes, language
  )
  values (
    current_user_id,
    encode(sha256(convert_to(new_token, 'UTF8')), 'hex'),
    coalesce(p_include_content, false),
    greatest(-840, least(840, coalesce(p_utc_offset_minutes, 0))),
    public.calendar_feed_clean_language(p_language)
  )
  on conflict (user_id) do update
  set token_hash = excluded.token_hash,
      include_content = excluded.include_content,
      utc_offset_minutes = excluded.utc_offset_minutes,
      language = excluded.language,
      created_at = now(),
      last_used_at = null,
      window_started_at = now(),
      window_count = 0;

  return new_token;
end;
$$;

create or replace function public.get_calendar_feed_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  feed public.calendar_feed_tokens%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select t.* into feed
  from public.calendar_feed_tokens t
  where t.user_id = current_user_id;

  if feed.user_id is null then
    return jsonb_build_object('enabled', false, 'include_content', false);
  end if;

  return jsonb_build_object(
    'enabled', true,
    'include_content', feed.include_content,
    'created_at', feed.created_at,
    'last_used_at', feed.last_used_at
  );
end;
$$;

create or replace function public.set_calendar_feed_options(
  p_include_content boolean,
  p_utc_offset_minutes integer default null,
  p_language text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.calendar_feed_tokens t
  set include_content = coalesce(p_include_content, t.include_content),
      utc_offset_minutes = coalesce(
        greatest(-840, least(840, p_utc_offset_minutes)),
        t.utc_offset_minutes
      ),
      language = case
        when p_language is null then t.language
        else public.calendar_feed_clean_language(p_language)
      end
  where t.user_id = auth.uid();
end;
$$;

create or replace function public.delete_calendar_feed_token()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  delete from public.calendar_feed_tokens where user_id = auth.uid();
end;
$$;

revoke execute on function public.create_calendar_feed_token(boolean, integer, text) from public, anon;
revoke execute on function public.get_calendar_feed_settings() from public, anon;
revoke execute on function public.set_calendar_feed_options(boolean, integer, text) from public, anon;
revoke execute on function public.delete_calendar_feed_token() from public, anon;
grant execute on function public.create_calendar_feed_token(boolean, integer, text) to authenticated;
grant execute on function public.get_calendar_feed_settings() to authenticated;
grant execute on function public.set_calendar_feed_options(boolean, integer, text) to authenticated;
grant execute on function public.delete_calendar_feed_token() to authenticated;
