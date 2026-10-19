-- Notes 2.0 (roadmap D5), part 4 of 5: publishing a note as a web page.
--
-- A note can be published on the web, for people without WeCord: the app
-- shows it read-only at https://<site>/n/<token> (the page reads it from the
-- note-public Edge Function). Off by default, and per note: only the note an
-- editor explicitly publishes.
--
-- * The link is a 192-bit random token, one per published note, made here
--   when the note is published (publish_note) and gone when it is withdrawn
--   (unpublish_note); publishing it again makes a new one, so an old link
--   never comes back to life. The token is kept as it is (the page is
--   public to anyone holding it anyway, and the people who can edit the note
--   need to see the link again): the table is closed to the API, only
--   publish_note and get_note_publication hand it out, and only to people
--   who can edit the note. Nothing lists tokens; a guess is 1 in 2^192.
-- * Who: publishing and changing the search-engine choice need edit rights
--   on the note (can_current_user_edit_note: they can send there, and when
--   the note is locked, manage it). Withdrawing is open to the people who
--   can edit, to its managers, and to whoever published it.
-- * public_note_by_token is what the Edge Function asks (service role only).
--   It answers "invalid" - the same word for every reason - when the token is
--   unknown, the note is deleted, the circle it lives in is suspended (K1),
--   or the person who published it has left the conversation, lost the right
--   to see it or deleted their account. What it hands out is the title, icon
--   and blocks; mentions of people are taken out of the text marks, and of
--   the props only what each kind of block needs. No comments, no history, no
--   names, no ids of people.
-- * allow_indexing is the author's choice to let search engines list the
--   page (off by default: the page says noindex).
-- * Deleting a note withdraws it; so does deleting the account (see
--   202610240340).

create table if not exists public.note_publications (
  note_id uuid primary key references public.notes(id) on delete cascade,
  token text not null,
  published_by uuid not null references public.profiles(id) on delete cascade,
  published_at timestamptz not null default now(),
  allow_indexing boolean not null default false,
  constraint note_publications_token check (token ~ '^[0-9a-f]{48}$')
);

create unique index if not exists note_publications_token_idx
  on public.note_publications (token);
create index if not exists note_publications_publisher_idx
  on public.note_publications (published_by);

alter table public.note_publications enable row level security;
revoke all on public.note_publications from anon, authenticated;
-- Read and written through the functions below only.

-- Whether a publication still stands: the note is not deleted, its circle is
-- not suspended, and the person who published it can still see it.
create or replace function public.note_publication_alive(pub public.note_publications)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.notes n
    join public.profiles p on p.id = pub.published_by
    where n.id = pub.note_id
      and n.deleted_at is null
      and p.deleted_at is null
      and public.note_user_can_view(pub.published_by, n.conversation_id)
  );
$$;

revoke execute on function public.note_publication_alive(public.note_publications) from public, anon, authenticated;

-- What the page of a block may carry of its props.
create or replace function public.note_public_props(p_kind text, p_props jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
  from jsonb_each(coalesce(p_props, '{}'::jsonb)) e
  where e.key = any (
    case p_kind
      when 'image' then array['path', 'name', 'width', 'height']
      when 'todo' then array['checked']
      when 'code' then array['lang']
      when 'table' then array['header', 'cols', 'rows']
      else array[]::text[]
    end
  );
$$;

revoke execute on function public.note_public_props(text, jsonb) from public, anon, authenticated;

-- The state of a note's publication, for people who can see the note. Only
-- people who can edit it get the token.
create or replace function public.get_note_publication(p_note_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  n public.notes%rowtype;
  pub public.note_publications%rowtype;
  can_publish boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  can_publish := public.can_current_user_edit_note(n.id);
  select * into pub from public.note_publications where note_id = n.id;
  if pub.note_id is null or not public.note_publication_alive(pub) then
    return jsonb_build_object('published', false, 'can_publish', can_publish);
  end if;
  return jsonb_build_object(
    'published', true,
    'can_publish', can_publish,
    'can_withdraw', can_publish
      or public.can_current_user_manage_note(n.id)
      or pub.published_by = auth.uid(),
    'token', case when can_publish then pub.token end,
    'allow_indexing', pub.allow_indexing,
    'published_at', pub.published_at,
    'published_by_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p where p.id = pub.published_by
    )
  );
end;
$$;

-- Publishes the note (or changes the search-engine choice of a published
-- one) and returns the state, token included.
create or replace function public.publish_note(
  p_note_id uuid,
  p_allow_indexing boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  pub public.note_publications%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_edit_note(n.id) then
    raise exception 'Only people who can edit the note can publish it'
      using errcode = '42501';
  end if;

  select * into pub from public.note_publications where note_id = n.id;
  if pub.note_id is not null and public.note_publication_alive(pub) then
    update public.note_publications
    set allow_indexing = coalesce(p_allow_indexing, false)
    where note_id = n.id;
  else
    -- Never published, or the publisher is gone: a new link.
    delete from public.note_publications where note_id = n.id;
    insert into public.note_publications (note_id, token, published_by, allow_indexing)
    values (
      n.id,
      encode(extensions.gen_random_bytes(24), 'hex'),
      uid,
      coalesce(p_allow_indexing, false)
    );
  end if;
  return public.get_note_publication(n.id);
end;
$$;

-- Withdraws the page: the link stops working at once.
create or replace function public.unpublish_note(p_note_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  pub public.note_publications%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into n from public.notes where id = p_note_id and deleted_at is null for update;
  if n.id is null or not public.is_current_user_conversation_member(n.conversation_id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  select * into pub from public.note_publications where note_id = n.id;
  if pub.note_id is null then
    return;
  end if;
  if not (
    public.can_current_user_edit_note(n.id)
    or public.can_current_user_manage_note(n.id)
    or pub.published_by = uid
  ) then
    raise exception 'You cannot withdraw this page' using errcode = '42501';
  end if;
  delete from public.note_publications where note_id = n.id;
end;
$$;

-- What the note-public Edge Function asks for (service role only): the page
-- of a token, or {"status": "invalid"}.
create or replace function public.public_note_by_token(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  pub public.note_publications%rowtype;
  n public.notes%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{48}$' then
    return jsonb_build_object('status', 'invalid');
  end if;
  select * into pub from public.note_publications where token = p_token;
  if pub.note_id is null or not public.note_publication_alive(pub) then
    return jsonb_build_object('status', 'invalid');
  end if;
  select * into n from public.notes where id = pub.note_id;
  return jsonb_build_object(
    'status', 'ok',
    'note_id', n.id,
    'title', n.title,
    'icon', n.icon,
    'updated_at', n.updated_at,
    'allow_indexing', pub.allow_indexing,
    'blocks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', b.id,
          'kind', b.kind,
          'text', b.text,
          'marks', public.note_marks_without_mentions(b.marks),
          'props', public.note_public_props(b.kind, b.props)
        )
        order by b.pos, b.id
      )
      from (
        select *
        from public.note_blocks nb
        where nb.note_id = n.id and not nb.deleted
        order by nb.pos, nb.id
        limit 5000
      ) b
    ), '[]'::jsonb)
  );
end;
$$;

-- A deleted note is withdrawn.
create or replace function public.unpublish_deleted_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.note_publications where note_id = new.id;
  return new;
end;
$$;

revoke execute on function public.unpublish_deleted_note() from public, anon, authenticated;

drop trigger if exists notes_unpublish_deleted on public.notes;
create trigger notes_unpublish_deleted
  after update of deleted_at on public.notes
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.unpublish_deleted_note();

revoke execute on function public.get_note_publication(uuid) from public, anon;
revoke execute on function public.publish_note(uuid, boolean) from public, anon;
revoke execute on function public.unpublish_note(uuid) from public, anon;
grant execute on function public.get_note_publication(uuid) to authenticated;
grant execute on function public.publish_note(uuid, boolean) to authenticated;
grant execute on function public.unpublish_note(uuid) to authenticated;

revoke execute on function public.public_note_by_token(text) from public, anon, authenticated;
grant execute on function public.public_note_by_token(text) to service_role;
