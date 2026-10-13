-- Cached Open Graph metadata for links in messages. Rows are written only by
-- the link-preview Edge Function with the service role; signed-in users read
-- them. Failed fetches are cached too (status <> 'ok') so a broken link is not
-- refetched on every render.
create table if not exists public.link_previews (
  url text primary key check (char_length(url) between 1 and 2048),
  title text,
  description text,
  image_url text,
  site_name text,
  status text not null default 'ok'
    check (status in ('ok', 'error', 'blocked', 'unsupported')),
  fetched_at timestamptz not null default now()
);

alter table public.link_previews enable row level security;

create policy link_previews_select_authenticated
  on public.link_previews for select
  to authenticated
  using (true);

revoke insert, update, delete, truncate on public.link_previews from anon;
revoke insert, update, delete, truncate on public.link_previews from authenticated;

-- The sender can hide the preview card under one of their messages.
alter table public.messages
  add column if not exists suppress_embeds boolean not null default false;

create or replace function public.set_message_suppress_embeds(
  target_message_id uuid,
  suppress boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_message_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.messages m
  set suppress_embeds = coalesce(suppress, true)
  where m.id = target_message_id
    and m.sender_id = auth.uid()
    and m.type = 'text'
    and m.recalled_at is null
    and public.is_current_user_conversation_member(m.conversation_id)
  returning m.id into updated_message_id;

  if updated_message_id is null then
    raise exception 'Message not found or caller cannot change its embeds'
      using errcode = '42501';
  end if;
end;
$$;

grant execute on function public.set_message_suppress_embeds(uuid, boolean) to authenticated;
