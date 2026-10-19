-- Notes 2.0 (roadmap D5), part 2 of 5: comments on a note.
--
-- A comment is a conversation about a note, kept apart from the note's text:
--
-- * A top-level comment is anchored: to a stretch of a block's text
--   (block_id + anchor_start/anchor_end, UTF-16 offsets like marks, plus
--   anchor_text, the words it was made on), to a whole block (no offsets),
--   or to nothing (a comment on the note). Replies hang under a top-level
--   comment (parent_id) and carry no anchor. Only a top-level comment can be
--   resolved, and that resolves its replies with it.
-- * The words a comment quotes are checked against the block, so nobody can
--   attach a made-up quotation to a note. If the block is later edited or
--   deleted the comment stays; the app shows the quotation as it was.
-- * A comment can mention people. Only members who can still see the note
--   (and who are not blocked either way) are kept, and each gets a row in
--   note_comment_notifications (the same goes for the author of the comment
--   that was replied to). The notifications page lists them.
--
-- Who may do what (all enforced here):
-- * read: whoever can see the note (can_current_user_view_note, which asks
--   for membership and the channel's view permission and says no in a
--   suspended circle) - except comments by people blocked either way;
-- * write: whoever can write notes there (can_current_user_write_docs: they
--   can send messages, and nobody in a direct chat has blocked the other).
--   Editing is not needed: a note only managers can edit takes comments from
--   everyone who can send;
-- * edit a comment: its author; delete: the author or a manager of the note;
--   resolve and reopen: anybody who can comment.
--
-- The table is read-only for clients (members read it so that Realtime can
-- tell the open note); every write goes through the functions below.
-- Deleting a note deletes its comments.

create table if not exists public.note_comments (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  parent_id uuid references public.note_comments(id) on delete cascade,
  block_id uuid,
  anchor_start integer,
  anchor_end integer,
  anchor_text text,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  mentions uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id) on delete set null,
  constraint note_comments_body_length
    check (char_length(body) between 1 and 2000),
  constraint note_comments_anchor_text_length
    check (anchor_text is null or char_length(anchor_text) between 1 and 300),
  constraint note_comments_anchor_range
    check (
      (anchor_start is null and anchor_end is null)
      or (block_id is not null
        and anchor_start >= 0
        and anchor_end > anchor_start
        and anchor_end <= 20000)
    ),
  constraint note_comments_reply_has_no_anchor
    check (parent_id is null or (block_id is null and anchor_text is null)),
  constraint note_comments_mentions_size
    check (cardinality(mentions) <= 20)
);

create index if not exists note_comments_note_idx
  on public.note_comments (note_id, created_at, id);
create index if not exists note_comments_parent_idx
  on public.note_comments (parent_id)
  where parent_id is not null;
create index if not exists note_comments_author_idx
  on public.note_comments (author_id);

-- A reply goes under a top-level comment of the same note.
create or replace function public.note_comments_check_parent()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  p public.note_comments%rowtype;
begin
  if new.parent_id is not null then
    select * into p from public.note_comments where id = new.parent_id;
    if p.id is null or p.note_id <> new.note_id or p.parent_id is not null then
      raise exception 'A reply goes under a comment of the same note'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function public.note_comments_check_parent() from public, anon, authenticated;

drop trigger if exists note_comments_check_parent on public.note_comments;
create trigger note_comments_check_parent
  before insert on public.note_comments
  for each row execute function public.note_comments_check_parent();

alter table public.note_comments enable row level security;
revoke all on public.note_comments from anon, authenticated;
grant select on public.note_comments to authenticated;

-- Whether [viewer] may see a comment by [author] (under [parent_comment]):
-- not when either is blocked by the other, and not a reply under a comment
-- they may not see.
create or replace function public.note_comment_visible_to(
  author uuid,
  parent_comment uuid,
  viewer uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select viewer is not null
    and (author = viewer or not public.are_users_blocked(viewer, author))
    and (
      parent_comment is null
      or exists (
        select 1
        from public.note_comments root
        where root.id = parent_comment
          and (root.author_id = viewer
            or not public.are_users_blocked(viewer, root.author_id))
      )
    );
$$;

revoke execute on function public.note_comment_visible_to(uuid, uuid, uuid) from public, anon;
grant execute on function public.note_comment_visible_to(uuid, uuid, uuid) to authenticated;

drop policy if exists note_comments_select_member on public.note_comments;
create policy note_comments_select_member
  on public.note_comments for select
  to authenticated
  using (
    public.can_current_user_view_note(note_id)
    and public.note_comment_visible_to(author_id, parent_id, auth.uid())
  );

-- Whether [p_user] belongs to the conversation and may see it (the circle
-- channel's view permission, and not in a suspended circle).
create or replace function public.note_user_can_view(
  p_user uuid,
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user is not null
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = p_conversation_id
        and cm.user_id = p_user
    )
    and not public.conversation_in_suspended_circle(p_conversation_id)
    and public.user_has_conversation_channel_permission(
      p_conversation_id, p_user, 'view_channel'
    );
$$;

revoke execute on function public.note_user_can_view(uuid, uuid) from public, anon, authenticated;

-- Whether the current user may comment on the note.
create or replace function public.can_current_user_comment_note(target_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.notes n
      where n.id = target_note_id
        and n.deleted_at is null
        and public.can_current_user_write_docs(n.conversation_id)
    );
$$;

revoke execute on function public.can_current_user_comment_note(uuid) from public, anon;
grant execute on function public.can_current_user_comment_note(uuid) to authenticated;

-- The people told about a comment: mentions and the author of the comment
-- being replied to.
create table if not exists public.note_comment_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  comment_id uuid not null references public.note_comments(id) on delete cascade,
  note_id uuid not null references public.notes(id) on delete cascade,
  kind text not null,
  actor_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint note_comment_notifications_kind check (kind in ('mention', 'reply')),
  constraint note_comment_notifications_once unique (user_id, comment_id)
);

create index if not exists note_comment_notifications_user_idx
  on public.note_comment_notifications (user_id, created_at desc);

alter table public.note_comment_notifications enable row level security;
revoke all on public.note_comment_notifications from anon, authenticated;
-- Read through list_note_comment_notifications only.

-- JSON of one comment for the person asking.
create or replace function public.note_comment_json(c public.note_comments)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', c.id,
    'note_id', c.note_id,
    'parent_id', c.parent_id,
    'block_id', c.block_id,
    'anchor_start', c.anchor_start,
    'anchor_end', c.anchor_end,
    'anchor_text', c.anchor_text,
    'author_id', c.author_id,
    'author_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p where p.id = c.author_id
    ),
    'author_avatar_url', (
      select p.avatar_url from public.profiles p where p.id = c.author_id
    ),
    'body', c.body,
    'mentions', to_jsonb(c.mentions),
    'created_at', c.created_at,
    'edited_at', c.edited_at,
    'resolved_at', c.resolved_at,
    'resolved_by_name', (
      select coalesce(nullif(btrim(p.display_name), ''), p.username)
      from public.profiles p where p.id = c.resolved_by
    ),
    'can_edit', c.author_id = auth.uid()
      and public.can_current_user_comment_note(c.note_id),
    'can_delete', c.author_id = auth.uid()
      or public.can_current_user_manage_note(c.note_id),
    'can_resolve', c.parent_id is null
      and public.can_current_user_comment_note(c.note_id)
  );
$$;

revoke execute on function public.note_comment_json(public.note_comments) from public, anon, authenticated;

-- The comments of a note, oldest first, as a list of JSON objects (top-level
-- comments and replies together; the app groups them by parent_id).
create or replace function public.list_note_comments(p_note_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.can_current_user_view_note(p_note_id)
    or not exists (
      select 1 from public.notes n
      where n.id = p_note_id and n.deleted_at is null
    )
  then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  return query
  select public.note_comment_json(c)
  from public.note_comments c
  where c.note_id = p_note_id
    and public.note_comment_visible_to(c.author_id, c.parent_id, auth.uid())
  order by c.created_at, c.id
  limit 2000;
end;
$$;

-- Adds a comment (or a reply, when [p_parent_id] is set). [p_id] lets an app
-- that lost the answer send it again safely.
create or replace function public.add_note_comment(
  p_note_id uuid,
  p_body text,
  p_block_id uuid default null,
  p_anchor_start integer default null,
  p_anchor_end integer default null,
  p_anchor_text text default null,
  p_parent_id uuid default null,
  p_mentions uuid[] default '{}',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n public.notes%rowtype;
  body_text text := btrim(coalesce(p_body, ''));
  parent public.note_comments%rowtype;
  b public.note_blocks%rowtype;
  existing public.note_comments%rowtype;
  created public.note_comments%rowtype;
  quote text := nullif(p_anchor_text, '');
  keep uuid[] := '{}';
  candidate uuid;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_id is not null then
    select * into existing from public.note_comments where id = p_id;
    if existing.id is not null then
      -- Sent before (the answer got lost).
      if existing.author_id is distinct from uid
        or not public.can_current_user_view_note(existing.note_id)
      then
        raise exception 'Note not found' using errcode = 'P0002';
      end if;
      return public.note_comment_json(existing);
    end if;
  end if;

  select * into n from public.notes where id = p_note_id and deleted_at is null;
  if n.id is null or not public.can_current_user_view_note(n.id) then
    raise exception 'Note not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_comment_note(n.id) then
    raise exception 'You cannot comment on this note' using errcode = '42501';
  end if;
  if char_length(body_text) not between 1 and 2000 then
    raise exception 'A comment has 1 to 2000 characters' using errcode = '22023';
  end if;

  if p_parent_id is not null then
    select * into parent from public.note_comments where id = p_parent_id;
    if parent.id is null
      or parent.note_id <> n.id
      or parent.parent_id is not null
      or not public.note_comment_visible_to(parent.author_id, null, uid)
    then
      raise exception 'Comment not found' using errcode = 'P0002';
    end if;
    if (select count(*) from public.note_comments where parent_id = parent.id) >= 200 then
      raise exception 'This thread has too many replies' using errcode = '22023';
    end if;
  else
    if (select count(*) from public.note_comments
        where note_id = n.id and parent_id is null) >= 500 then
      raise exception 'This note has too many comments' using errcode = '22023';
    end if;
    if p_block_id is not null then
      select * into b
      from public.note_blocks
      where id = p_block_id and note_id = n.id and not deleted;
      if b.id is null then
        raise exception 'That part of the note is gone' using errcode = '22023';
      end if;
      if (p_anchor_start is null) <> (p_anchor_end is null) then
        raise exception 'An anchor has a start and an end' using errcode = '22023';
      end if;
      if p_anchor_start is not null
        and (p_anchor_start < 0 or p_anchor_end <= p_anchor_start or p_anchor_end > 20000)
      then
        raise exception 'Bad anchor' using errcode = '22023';
      end if;
      -- The quotation must be words of the block.
      if quote is not null
        and (b.kind = 'table' or char_length(quote) > 300 or strpos(b.text, quote) = 0)
      then
        raise exception 'The quoted words are not in that part of the note'
          using errcode = '22023';
      end if;
    else
      if p_anchor_start is not null or p_anchor_end is not null or quote is not null then
        raise exception 'An anchor needs a block' using errcode = '22023';
      end if;
    end if;
  end if;

  -- People to tell: members who can see the note, not the author, not
  -- blocked either way.
  if p_mentions is not null and cardinality(p_mentions) > 0 then
    for candidate in
      select distinct m from unnest(p_mentions[1:20]) m
    loop
      if candidate is not null
        and candidate <> uid
        and public.note_user_can_view(candidate, n.conversation_id)
        and not public.are_users_blocked(uid, candidate)
        and exists (
          select 1 from public.profiles p
          where p.id = candidate and p.deleted_at is null
        )
      then
        keep := keep || candidate;
      end if;
    end loop;
  end if;

  insert into public.note_comments (
    id, note_id, parent_id, block_id, anchor_start, anchor_end, anchor_text,
    author_id, body, mentions
  )
  values (
    coalesce(p_id, gen_random_uuid()),
    n.id,
    p_parent_id,
    case when p_parent_id is null then p_block_id end,
    case when p_parent_id is null and p_block_id is not null then p_anchor_start end,
    case when p_parent_id is null and p_block_id is not null then p_anchor_end end,
    case when p_parent_id is null and p_block_id is not null then quote end,
    uid,
    body_text,
    keep
  )
  returning * into created;

  if cardinality(keep) > 0 then
    insert into public.note_comment_notifications (user_id, comment_id, note_id, kind, actor_id)
    select m, created.id, n.id, 'mention', uid from unnest(keep) m
    on conflict (user_id, comment_id) do nothing;
  end if;
  if p_parent_id is not null
    and parent.author_id <> uid
    and not (parent.author_id = any (keep))
    and public.note_user_can_view(parent.author_id, n.conversation_id)
    and not public.are_users_blocked(uid, parent.author_id)
    and exists (
      select 1 from public.profiles p
      where p.id = parent.author_id and p.deleted_at is null
    )
  then
    insert into public.note_comment_notifications (user_id, comment_id, note_id, kind, actor_id)
    values (parent.author_id, created.id, n.id, 'reply', uid)
    on conflict (user_id, comment_id) do nothing;
  end if;

  return public.note_comment_json(created);
end;
$$;

-- The author changes the words of a comment.
create or replace function public.edit_note_comment(
  p_comment_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.note_comments%rowtype;
  body_text text := btrim(coalesce(p_body, ''));
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.note_comments where id = p_comment_id for update;
  if c.id is null
    or not public.can_current_user_view_note(c.note_id)
    or c.author_id <> uid
  then
    raise exception 'Comment not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_comment_note(c.note_id) then
    raise exception 'You cannot comment on this note' using errcode = '42501';
  end if;
  if char_length(body_text) not between 1 and 2000 then
    raise exception 'A comment has 1 to 2000 characters' using errcode = '22023';
  end if;
  update public.note_comments
  set body = body_text, edited_at = now()
  where id = c.id
  returning * into c;
  return public.note_comment_json(c);
end;
$$;

-- Deletes a comment (and the replies under it): its author, or a manager of
-- the note.
create or replace function public.delete_note_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.note_comments%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.note_comments where id = p_comment_id;
  if c.id is null or not public.can_current_user_view_note(c.note_id) then
    raise exception 'Comment not found' using errcode = 'P0002';
  end if;
  if c.author_id <> uid and not public.can_current_user_manage_note(c.note_id) then
    raise exception 'Only the author or a manager can delete this comment'
      using errcode = '42501';
  end if;
  delete from public.note_comments where id = c.id;
end;
$$;

-- Resolves a top-level comment, or opens it again.
create or replace function public.resolve_note_comment(
  p_comment_id uuid,
  p_resolved boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.note_comments%rowtype;
begin
  if uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into c from public.note_comments where id = p_comment_id for update;
  if c.id is null
    or c.parent_id is not null
    or not public.can_current_user_view_note(c.note_id)
    or not public.note_comment_visible_to(c.author_id, null, uid)
  then
    raise exception 'Comment not found' using errcode = 'P0002';
  end if;
  if not public.can_current_user_comment_note(c.note_id) then
    raise exception 'You cannot comment on this note' using errcode = '42501';
  end if;
  update public.note_comments
  set resolved_at = case when coalesce(p_resolved, true) then now() end,
      resolved_by = case when coalesce(p_resolved, true) then uid end
  where id = c.id
  returning * into c;
  return public.note_comment_json(c);
end;
$$;

-- The caller's comment notifications of the last 30 days, newest first, for
-- notes they can still see.
create or replace function public.list_note_comment_notifications(
  p_limit integer default 50
)
returns table (
  id uuid,
  kind text,
  comment_id uuid,
  note_id uuid,
  conversation_id uuid,
  note_title text,
  note_icon text,
  actor_id uuid,
  actor_name text,
  actor_avatar_url text,
  snippet text,
  created_at timestamptz,
  is_unread boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
  select
    x.id,
    x.kind,
    x.comment_id,
    x.note_id,
    n.conversation_id,
    n.title,
    n.icon,
    x.actor_id,
    coalesce(nullif(btrim(p.display_name), ''), p.username),
    p.avatar_url,
    left(c.body, 200),
    x.created_at,
    x.read_at is null
  from public.note_comment_notifications x
  join public.note_comments c on c.id = x.comment_id
  join public.notes n on n.id = x.note_id and n.deleted_at is null
  left join public.profiles p on p.id = x.actor_id
  where x.user_id = auth.uid()
    and x.created_at > now() - interval '30 days'
    and public.is_current_user_conversation_member(n.conversation_id)
    and (x.actor_id is null or not public.are_users_blocked(auth.uid(), x.actor_id))
  order by x.created_at desc, x.id
  limit greatest(1, least(coalesce(p_limit, 50), 100));
end;
$$;

-- Marks notifications read (all of them when [p_ids] is null).
create or replace function public.mark_note_comment_notifications_read(
  p_ids uuid[] default null
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
  update public.note_comment_notifications x
  set read_at = now()
  where x.user_id = auth.uid()
    and x.read_at is null
    and (p_ids is null or x.id = any (p_ids));
end;
$$;

-- A deleted note takes its comments with it.
create or replace function public.erase_comments_of_deleted_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.note_comments where note_id = new.id;
  return new;
end;
$$;

revoke execute on function public.erase_comments_of_deleted_note() from public, anon, authenticated;

drop trigger if exists notes_erase_comments on public.notes;
create trigger notes_erase_comments
  after update of deleted_at on public.notes
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function public.erase_comments_of_deleted_note();

revoke execute on function public.list_note_comments(uuid) from public, anon;
revoke execute on function public.add_note_comment(uuid, text, uuid, integer, integer, text, uuid, uuid[], uuid) from public, anon;
revoke execute on function public.edit_note_comment(uuid, text) from public, anon;
revoke execute on function public.delete_note_comment(uuid) from public, anon;
revoke execute on function public.resolve_note_comment(uuid, boolean) from public, anon;
revoke execute on function public.list_note_comment_notifications(integer) from public, anon;
revoke execute on function public.mark_note_comment_notifications_read(uuid[]) from public, anon;
grant execute on function public.list_note_comments(uuid) to authenticated;
grant execute on function public.add_note_comment(uuid, text, uuid, integer, integer, text, uuid, uuid[], uuid) to authenticated;
grant execute on function public.edit_note_comment(uuid, text) to authenticated;
grant execute on function public.delete_note_comment(uuid) to authenticated;
grant execute on function public.resolve_note_comment(uuid, boolean) to authenticated;
grant execute on function public.list_note_comment_notifications(integer) to authenticated;
grant execute on function public.mark_note_comment_notifications_read(uuid[]) to authenticated;

-- Realtime: the open note hears about new, edited, resolved and deleted
-- comments.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = 'note_comments'
    ) then
      alter publication supabase_realtime add table public.note_comments;
    end if;
  end if;
end;
$$;
