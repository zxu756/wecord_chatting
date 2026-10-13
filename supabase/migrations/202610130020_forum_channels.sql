-- Forum channels, like Discord's: a circle channel of kind 'forum' holds
-- posts instead of a chat. Each post is a thread (202610130011) of the
-- forum channel's conversation, without a root message; the post's body is
-- the first message of the thread's conversation, and replies follow it.
-- Threads already share their channel's members, permissions (view_channel
-- hides a private forum's posts, send_messages gates posting and
-- replying), unread counts, notifications and circle rail counts.
--
-- * conversation_threads.is_pinned: pinned posts are listed first.
-- * forum_tags (at most 20 per forum, names of 1 to 20 characters, unique
--   per forum regardless of case, with an optional emoji) and thread_tags
--   (at most 5 per post). Clients only read them; RPCs write them.
-- * create_forum_post(target_channel_id, post_title, post_body, tag_ids,
--   post_attachment): needs send_messages in the forum and creates the
--   thread, its first message and its tags at once. An image attachment
--   is uploaded to the forum conversation's chat-images folder first.
-- * list_forum_posts(target_channel_id, sort_order, filter_tag_id,
--   before_at, before_id, limit_count): pinned posts (first page only),
--   then a page of the others by latest activity or creation, newest
--   first; the cursor is the last post's sort time and id.
-- * set_forum_post_tags (the post's author or members with
--   manage_messages), pin_forum_post (manage_messages), and forum tag CRUD
--   create_forum_tag / update_forum_tag / delete_forum_tag /
--   reorder_forum_tags (manage_channels). Tag changes and pins are logged
--   as forum_tag_create, forum_tag_update, forum_tag_delete,
--   forum_tag_reorder, forum_post_pin and forum_post_unpin.
-- * The forum channel's own conversation takes no messages (the send
--   trigger refuses them) and create_thread refuses forum channels: posts
--   are created with create_forum_post only.
-- * create_circle_channel accepts target_kind 'forum'; get_circle_detail
--   returns each forum's tags.

alter table public.conversation_threads
  add column if not exists is_pinned boolean not null default false;

create table if not exists public.forum_tags (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null,
  channel_id uuid not null,
  name text not null,
  emoji text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  constraint forum_tags_name_length check (
    name = btrim(name) and char_length(name) between 1 and 20
  ),
  constraint forum_tags_emoji_length check (
    emoji is null or char_length(emoji) between 1 and 32
  ),
  constraint forum_tags_channel_fkey
    foreign key (channel_id, circle_id)
    references public.circle_channels(id, circle_id)
    on delete cascade,
  constraint forum_tags_id_channel_unique unique (id, channel_id)
);

create unique index if not exists forum_tags_channel_name_idx
  on public.forum_tags (channel_id, lower(name));

create table if not exists public.thread_tags (
  thread_id uuid not null
    references public.conversation_threads(id) on delete cascade,
  tag_id uuid not null,
  channel_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (thread_id, tag_id),
  constraint thread_tags_tag_fkey
    foreign key (tag_id, channel_id)
    references public.forum_tags(id, channel_id)
    on delete cascade
);

create index if not exists thread_tags_tag_idx on public.thread_tags (tag_id);

create index if not exists conversation_threads_parent_created_idx
  on public.conversation_threads (parent_conversation_id, created_at desc);

-- Realtime matches DELETE events against the old row, so keep the circle
-- and channel in it.
alter table public.forum_tags replica identity full;
alter table public.thread_tags replica identity full;

alter table public.forum_tags enable row level security;
alter table public.thread_tags enable row level security;

revoke insert, update, delete, truncate on public.forum_tags from anon;
revoke insert, update, delete, truncate on public.forum_tags from authenticated;
revoke insert, update, delete, truncate on public.thread_tags from anon;
revoke insert, update, delete, truncate on public.thread_tags from authenticated;

drop policy if exists forum_tags_select_viewer on public.forum_tags;
create policy forum_tags_select_viewer
  on public.forum_tags for select
  to authenticated
  using (
    public.is_current_user_circle_member(circle_id)
    and public.current_user_has_channel_permission(channel_id, 'view_channel')
  );

drop policy if exists thread_tags_select_viewer on public.thread_tags;
create policy thread_tags_select_viewer
  on public.thread_tags for select
  to authenticated
  using (public.current_user_has_channel_permission(channel_id, 'view_channel'));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'forum_tags'
  ) then
    alter publication supabase_realtime add table public.forum_tags;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'thread_tags'
  ) then
    alter publication supabase_realtime add table public.thread_tags;
  end if;
end $$;

-- The forum channel the caller manages ([permission_name]) and can see, or
-- an error. Only for the RPCs below.
create or replace function public.forum_channel_for_management(
  target_channel_id uuid,
  permission_name text
)
returns public.circle_channels
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.current_user_has_channel_permission(
      target_channel_id,
      'view_channel'
    )
    or not public.current_user_has_channel_permission(
      target_channel_id,
      permission_name
    )
  then
    raise exception 'Channel not found or caller lacks permission'
      using errcode = '42501';
  end if;

  if channel.kind <> 'forum' then
    raise exception 'Channel is not a forum' using errcode = '22023';
  end if;

  return channel;
end;
$$;

revoke execute on function public.forum_channel_for_management(uuid, text) from public;
revoke execute on function public.forum_channel_for_management(uuid, text) from anon;
revoke execute on function public.forum_channel_for_management(uuid, text) from authenticated;

-- Tag ids for a post: distinct, at most 5, all of [target_channel_id].
create or replace function public.normalize_forum_tag_ids(
  target_channel_id uuid,
  tag_ids uuid[]
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  normalized uuid[];
begin
  select coalesce(array_agg(distinct tag_id), array[]::uuid[])
  into normalized
  from unnest(coalesce(tag_ids, array[]::uuid[])) as tag_id
  where tag_id is not null;

  if cardinality(normalized) > 5 then
    raise exception 'A post can have at most 5 tags' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(normalized) as tag_id
    where not exists (
      select 1
      from public.forum_tags ft
      where ft.id = tag_id
        and ft.channel_id = target_channel_id
    )
  ) then
    raise exception 'Tag does not belong to this forum' using errcode = '22023';
  end if;

  return normalized;
end;
$$;

revoke execute on function public.normalize_forum_tag_ids(uuid, uuid[]) from public;
revoke execute on function public.normalize_forum_tag_ids(uuid, uuid[]) from anon;
revoke execute on function public.normalize_forum_tag_ids(uuid, uuid[]) from authenticated;

-- A post as the client lists it, for the current user.
create or replace function public.forum_post_payload(
  thread_row public.conversation_threads,
  forum_channel public.circle_channels
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', thread_row.id,
    'conversation_id', thread_row.conversation_id,
    'channel_id', forum_channel.id,
    'title', thread_row.title,
    'created_by', thread_row.created_by,
    'created_at', thread_row.created_at,
    'last_activity_at', coalesce(thread_row.last_message_at, thread_row.created_at),
    'archived_at', thread_row.archived_at,
    'is_pinned', thread_row.is_pinned,
    'author', case
      when author.id is null then null
      else jsonb_build_object(
        'id', author.id,
        'username', author.username,
        'display_name', author.display_name,
        'avatar_url', author.avatar_url,
        'bio', author.bio,
        'created_at', author.created_at,
        'updated_at', author.updated_at,
        'nickname', author_member.nickname,
        'role_color', (
          select r.color
          from public.circle_member_roles mr
          join public.circle_roles r on r.id = mr.role_id
          where mr.circle_id = forum_channel.circle_id
            and mr.user_id = author.id
            and r.color is not null
          order by r.position desc
          limit 1
        )
      )
    end,
    'tags', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ft.id,
          'channel_id', ft.channel_id,
          'name', ft.name,
          'emoji', ft.emoji,
          'position', ft.position
        )
        order by ft.position, ft.created_at
      )
      from public.thread_tags tt
      join public.forum_tags ft on ft.id = tt.tag_id
      where tt.thread_id = thread_row.id
    ), '[]'::jsonb),
    'opening_message', case
      when opening.id is null then null
      else jsonb_build_object(
        'id', opening.id,
        'type', opening.type,
        'body', case when opening.recalled_at is null then opening.body else '' end,
        'recalled', opening.recalled_at is not null
      )
    end,
    'reply_count', (
      select count(*)
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.type <> 'system'
        and m.recalled_at is null
        and m.id is distinct from opening.id
    ),
    'thumbnail', (
      select m.attachment
      from public.messages m
      where m.conversation_id = thread_row.conversation_id
        and m.recalled_at is null
        and m.type in ('text', 'image')
        and m.attachment ->> 'kind' = 'image'
      order by m.created_at, m.id
      limit 1
    ),
    'unread_count', (
      select count(*)
      from public.conversation_members cm
      left join public.messages read_message
        on read_message.id = cm.last_read_message_id
      join public.messages m
        on m.conversation_id = cm.conversation_id
        and m.sender_id <> auth.uid()
        and m.type <> 'system'
        and (
          read_message.created_at is null
          or m.created_at > read_message.created_at
        )
      where cm.conversation_id = thread_row.conversation_id
        and cm.user_id = auth.uid()
    ),
    'can_manage', public.can_current_user_manage_thread(thread_row.id)
  )
  from (select 1) as single_row
  left join public.profiles author on author.id = thread_row.created_by
  left join public.circle_members author_member
    on author_member.circle_id = forum_channel.circle_id
    and author_member.user_id = thread_row.created_by
  left join lateral (
    select m.id, m.type, m.body, m.recalled_at
    from public.messages m
    where m.conversation_id = thread_row.conversation_id
      and m.type <> 'system'
    order by m.created_at, m.id
    limit 1
  ) opening on true;
$$;

revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from public;
revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from anon;
revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from authenticated;

-- Creates a post: a thread of the forum channel, its first message (the
-- body, with an optional image) and its tags, all at once.
create or replace function public.create_forum_post(
  target_channel_id uuid,
  post_title text,
  post_body text,
  tag_ids uuid[] default array[]::uuid[],
  post_attachment jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  channel public.circle_channels%rowtype;
  normalized_title text := nullif(
    regexp_replace(btrim(coalesce(post_title, '')), '\s+', ' ', 'g'),
    ''
  );
  trimmed_body text := btrim(coalesce(post_body, ''));
  normalized_tag_ids uuid[];
  created_conversation_id uuid;
  created_thread public.conversation_threads%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.can_current_user_send_in_conversation(channel.conversation_id)
  then
    raise exception 'Channel not found or caller cannot post in it'
      using errcode = '42501';
  end if;

  if channel.kind <> 'forum' then
    raise exception 'Channel is not a forum' using errcode = '22023';
  end if;

  if normalized_title is null or char_length(normalized_title) > 100 then
    raise exception 'Post title must be between 1 and 100 characters'
      using errcode = '22023';
  end if;

  if char_length(trimmed_body) > 4000 then
    raise exception 'Post body must be at most 4000 characters'
      using errcode = '22023';
  end if;

  if post_attachment is not null and (
    jsonb_typeof(post_attachment) <> 'object'
    or post_attachment ->> 'kind' is distinct from 'image'
    or post_attachment ->> 'bucket' is distinct from 'chat-images'
    or coalesce(post_attachment ->> 'path', '')
      not like channel.conversation_id::text || '/%'
  ) then
    raise exception 'Post images must be uploaded to this forum'
      using errcode = '22023';
  end if;

  if char_length(trimmed_body) = 0 and post_attachment is null then
    raise exception 'Post body is required' using errcode = '22023';
  end if;

  normalized_tag_ids := public.normalize_forum_tag_ids(channel.id, tag_ids);

  insert into public.conversations (type, title)
  values ('thread', normalized_title)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, 'member'
  from public.conversation_members cm
  where cm.conversation_id = channel.conversation_id
  on conflict do nothing;

  insert into public.conversation_threads (
    parent_conversation_id,
    root_message_id,
    conversation_id,
    title,
    created_by
  )
  values (
    channel.conversation_id,
    null,
    created_conversation_id,
    normalized_title,
    current_user_id
  )
  returning * into created_thread;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    created_conversation_id,
    current_user_id,
    case when char_length(trimmed_body) = 0 then 'image' else 'text' end,
    trimmed_body,
    post_attachment
  );

  insert into public.thread_tags (thread_id, tag_id, channel_id)
  select created_thread.id, tag_id, channel.id
  from unnest(normalized_tag_ids) as tag_id;

  -- The first message bumped the thread's activity.
  select ct.* into created_thread
  from public.conversation_threads ct
  where ct.id = created_thread.id;

  return public.forum_post_payload(created_thread, channel);
end;
$$;

-- A page of a forum's posts (see the header).
create or replace function public.list_forum_posts(
  target_channel_id uuid,
  sort_order text default 'activity',
  filter_tag_id uuid default null,
  before_at timestamptz default null,
  before_id uuid default null,
  limit_count integer default 25
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  page_size integer := greatest(1, least(coalesce(limit_count, 25), 100));
  by_created boolean := sort_order = 'created';
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if sort_order is null or sort_order not in ('activity', 'created') then
    raise exception 'Sort must be activity or created' using errcode = '22023';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.id = target_channel_id;

  if channel.id is null
    or not public.is_current_user_conversation_member(channel.conversation_id)
  then
    raise exception 'Channel not found or caller cannot see it'
      using errcode = '42501';
  end if;

  if channel.kind <> 'forum' then
    raise exception 'Channel is not a forum' using errcode = '22023';
  end if;

  return query
  with candidates as (
    select
      ct.id,
      ct.is_pinned,
      case
        when by_created then ct.created_at
        else coalesce(ct.last_message_at, ct.created_at)
      end as sort_at
    from public.conversation_threads ct
    where ct.parent_conversation_id = channel.conversation_id
      and (
        filter_tag_id is null
        or exists (
          select 1
          from public.thread_tags tt
          where tt.thread_id = ct.id
            and tt.tag_id = filter_tag_id
        )
      )
  ),
  pinned as (
    select c.id, c.sort_at, 0 as grp
    from candidates c
    where c.is_pinned
      and before_at is null
  ),
  page as (
    select c.id, c.sort_at, 1 as grp
    from candidates c
    where not c.is_pinned
      and (
        before_at is null
        or c.sort_at < before_at
        or (before_id is not null and c.sort_at = before_at and c.id < before_id)
      )
    order by c.sort_at desc, c.id desc
    limit page_size
  ),
  chosen as (
    select * from pinned
    union all
    select * from page
  )
  select public.forum_post_payload(ct, channel)
  from chosen
  join public.conversation_threads ct on ct.id = chosen.id
  order by chosen.grp, chosen.sort_at desc, chosen.id desc;
end;
$$;

-- Replaces a post's tags; for its author and members with manage_messages
-- in the forum.
create or replace function public.set_forum_post_tags(
  target_thread_id uuid,
  tag_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  normalized_tag_ids uuid[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cc.* into channel
  from public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where ct.id = target_thread_id
    and cc.kind = 'forum';

  if channel.id is null
    or not public.can_current_user_manage_thread(target_thread_id)
  then
    raise exception 'Post not found or caller cannot edit its tags'
      using errcode = '42501';
  end if;

  -- Serialize edits of one post's tags.
  perform 1 from public.conversation_threads ct
  where ct.id = target_thread_id
  for update;

  normalized_tag_ids := public.normalize_forum_tag_ids(channel.id, tag_ids);

  delete from public.thread_tags tt
  where tt.thread_id = target_thread_id
    and not (tt.tag_id = any(normalized_tag_ids));

  insert into public.thread_tags (thread_id, tag_id, channel_id)
  select target_thread_id, tag_id, channel.id
  from unnest(normalized_tag_ids) as tag_id
  on conflict do nothing;
end;
$$;

-- Pins or unpins a post; needs manage_messages in the forum.
create or replace function public.pin_forum_post(
  target_thread_id uuid,
  pinned boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  updated_thread public.conversation_threads%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if pinned is null then
    raise exception 'Pinned must be true or false' using errcode = '22023';
  end if;

  select cc.* into channel
  from public.conversation_threads ct
  join public.circle_channels cc on cc.conversation_id = ct.parent_conversation_id
  where ct.id = target_thread_id
    and cc.kind = 'forum';

  if channel.id is null
    or not public.current_user_has_channel_permission(channel.id, 'view_channel')
    or not public.current_user_has_channel_permission(channel.id, 'manage_messages')
  then
    raise exception 'Post not found or caller cannot pin posts'
      using errcode = '42501';
  end if;

  update public.conversation_threads ct
  set is_pinned = pin_forum_post.pinned
  where ct.id = target_thread_id
    and ct.is_pinned is distinct from pin_forum_post.pinned
  returning * into updated_thread;

  if updated_thread.id is not null then
    perform public.write_circle_audit(
      channel.circle_id,
      case when pin_forum_post.pinned then 'forum_post_pin' else 'forum_post_unpin' end,
      'thread',
      updated_thread.id,
      updated_thread.title,
      jsonb_build_object(
        'channel_id', channel.id,
        'channel_name', channel.name,
        'created_by', updated_thread.created_by
      )
    );
  end if;
end;
$$;

-- Adds a tag at the end of a forum's tags; returns its id.
create or replace function public.create_forum_tag(
  target_channel_id uuid,
  tag_name text,
  tag_emoji text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  trimmed_name text := regexp_replace(btrim(coalesce(tag_name, '')), '\s+', ' ', 'g');
  trimmed_emoji text := nullif(btrim(coalesce(tag_emoji, '')), '');
  created_tag_id uuid;
begin
  channel := public.forum_channel_for_management(target_channel_id, 'manage_channels');

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 20 then
    raise exception 'Tag name must be between 1 and 20 characters'
      using errcode = '22023';
  end if;

  if trimmed_emoji is not null and char_length(trimmed_emoji) > 32 then
    raise exception 'Tag emoji is too long' using errcode = '22023';
  end if;

  -- Serialize tag changes per forum so the limit holds.
  perform 1 from public.circle_channels cc
  where cc.id = channel.id
  for no key update;

  if (select count(*) from public.forum_tags ft where ft.channel_id = channel.id) >= 20 then
    raise exception 'A forum can have at most 20 tags' using errcode = '54000';
  end if;

  if exists (
    select 1 from public.forum_tags ft
    where ft.channel_id = channel.id
      and lower(ft.name) = lower(trimmed_name)
  ) then
    raise exception 'This forum already has a tag with that name'
      using errcode = '23505';
  end if;

  insert into public.forum_tags (circle_id, channel_id, name, emoji, position)
  values (
    channel.circle_id,
    channel.id,
    trimmed_name,
    trimmed_emoji,
    coalesce((
      select max(ft.position) + 1
      from public.forum_tags ft
      where ft.channel_id = channel.id
    ), 0)
  )
  returning id into created_tag_id;

  perform public.write_circle_audit(
    channel.circle_id,
    'forum_tag_create',
    'tag',
    created_tag_id,
    trimmed_name,
    jsonb_build_object(
      'channel_id', channel.id,
      'channel_name', channel.name,
      'name', trimmed_name,
      'emoji', trimmed_emoji
    )
  );

  return created_tag_id;
end;
$$;

-- Renames a tag and sets its emoji (null or blank clears it).
create or replace function public.update_forum_tag(
  target_tag_id uuid,
  tag_name text,
  tag_emoji text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tag public.forum_tags%rowtype;
  channel public.circle_channels%rowtype;
  trimmed_name text := regexp_replace(btrim(coalesce(tag_name, '')), '\s+', ' ', 'g');
  trimmed_emoji text := nullif(btrim(coalesce(tag_emoji, '')), '');
  audit_changes jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ft.* into tag from public.forum_tags ft where ft.id = target_tag_id;
  if tag.id is null then
    raise exception 'Tag not found' using errcode = '42501';
  end if;

  channel := public.forum_channel_for_management(tag.channel_id, 'manage_channels');

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 20 then
    raise exception 'Tag name must be between 1 and 20 characters'
      using errcode = '22023';
  end if;

  if trimmed_emoji is not null and char_length(trimmed_emoji) > 32 then
    raise exception 'Tag emoji is too long' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.forum_tags ft
    where ft.channel_id = tag.channel_id
      and ft.id <> tag.id
      and lower(ft.name) = lower(trimmed_name)
  ) then
    raise exception 'This forum already has a tag with that name'
      using errcode = '23505';
  end if;

  if tag.name is distinct from trimmed_name then
    audit_changes := audit_changes || jsonb_build_object(
      'name', jsonb_build_object('old', tag.name, 'new', trimmed_name)
    );
  end if;

  if tag.emoji is distinct from trimmed_emoji then
    audit_changes := audit_changes || jsonb_build_object(
      'emoji', jsonb_build_object('old', tag.emoji, 'new', trimmed_emoji)
    );
  end if;

  if audit_changes = '{}'::jsonb then
    return;
  end if;

  update public.forum_tags ft
  set name = trimmed_name,
      emoji = trimmed_emoji
  where ft.id = tag.id;

  perform public.write_circle_audit(
    channel.circle_id,
    'forum_tag_update',
    'tag',
    tag.id,
    trimmed_name,
    audit_changes || jsonb_build_object(
      'channel_id', channel.id,
      'channel_name', channel.name
    )
  );
end;
$$;

-- Deletes a tag; posts lose it.
create or replace function public.delete_forum_tag(target_tag_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  tag public.forum_tags%rowtype;
  channel public.circle_channels%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ft.* into tag from public.forum_tags ft where ft.id = target_tag_id;
  if tag.id is null then
    raise exception 'Tag not found' using errcode = '42501';
  end if;

  channel := public.forum_channel_for_management(tag.channel_id, 'manage_channels');

  perform public.write_circle_audit(
    channel.circle_id,
    'forum_tag_delete',
    'tag',
    tag.id,
    tag.name,
    jsonb_build_object(
      'channel_id', channel.id,
      'channel_name', channel.name,
      'name', tag.name,
      'emoji', tag.emoji,
      'post_count', (
        select count(*) from public.thread_tags tt where tt.tag_id = tag.id
      )
    )
  );

  delete from public.forum_tags ft where ft.id = tag.id;
end;
$$;

-- Stores the order of every tag of a forum at once.
create or replace function public.reorder_forum_tags(
  target_channel_id uuid,
  tag_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  ordered_ids uuid[] := coalesce(tag_ids, array[]::uuid[]);
  changed integer;
begin
  channel := public.forum_channel_for_management(target_channel_id, 'manage_channels');

  perform 1 from public.circle_channels cc
  where cc.id = channel.id
  for no key update;

  if cardinality(ordered_ids) <> (
      select count(distinct tag_id) from unnest(ordered_ids) as tag_id
    )
    or cardinality(ordered_ids) <> (
      select count(*) from public.forum_tags ft where ft.channel_id = channel.id
    )
    or exists (
      select 1 from unnest(ordered_ids) as tag_id
      where not exists (
        select 1 from public.forum_tags ft
        where ft.id = tag_id and ft.channel_id = channel.id
      )
    )
  then
    raise exception 'Order must list every tag of the forum once'
      using errcode = '22023';
  end if;

  update public.forum_tags ft
  set position = ordered.position
  from (
    select item.tag_id, (item.ordinality - 1)::integer as position
    from unnest(ordered_ids) with ordinality as item(tag_id, ordinality)
  ) ordered
  where ft.id = ordered.tag_id
    and ft.position is distinct from ordered.position;
  get diagnostics changed = row_count;

  if changed > 0 then
    perform public.write_circle_audit(
      channel.circle_id,
      'forum_tag_reorder',
      'channel',
      channel.id,
      channel.name,
      jsonb_build_object(
        'tags', (
          select jsonb_agg(ft.name order by ft.position)
          from public.forum_tags ft
          where ft.channel_id = channel.id
        )
      )
    );
  end if;
end;
$$;

-- Same as 202610130019_channel_management, but forum channels can be created too.
create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text,
  target_category_id uuid default null,
  target_kind text default 'text'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  channel_kind text := coalesce(target_kind, 'text');
  created_conversation_id uuid;
  created_channel_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 48 then
    raise exception 'Channel name must be between 1 and 48 characters'
      using errcode = '22023';
  end if;

  if channel_kind not in ('text', 'forum') then
    raise exception 'Unsupported channel type' using errcode = '22023';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_channels'
  ) then
    raise exception 'Only members who can manage channels can create channels'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  if target_category_id is not null and not exists (
    select 1
    from public.circle_channel_categories ccc
    where ccc.id = target_category_id
      and ccc.circle_id = target_circle_id
  ) then
    raise exception 'Category does not belong to this circle'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('channel', trimmed_name)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = target_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    category_id,
    created_by,
    kind
  )
  values (
    target_circle_id,
    created_conversation_id,
    trimmed_name,
    coalesce((
      select max(position) + 1
      from public.circle_channels
      where circle_id = target_circle_id
    ), 0),
    target_category_id,
    current_user_id,
    channel_kind
  )
  returning id into created_channel_id;

  perform public.write_circle_audit(
    target_circle_id,
    'channel_create',
    'channel',
    created_channel_id,
    trimmed_name,
    jsonb_build_object(
      'name', trimmed_name,
      'kind', channel_kind,
      'category_id', target_category_id,
      'category_name', (
        select ccc.name
        from public.circle_channel_categories ccc
        where ccc.id = target_category_id
      )
    )
  );

  return created_channel_id;
end;
$$;

-- Same as 202610130015_channel_slowmode, but a forum channel's own conversation
-- takes no messages.
create or replace function public.check_channel_message_send()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  channel public.circle_channels%rowtype;
  last_sent_at timestamptz;
  remaining_seconds integer;
begin
  if new.type = 'system' then
    return new;
  end if;

  if not public.user_has_conversation_channel_permission(
    new.conversation_id,
    new.sender_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  select cc.* into channel
  from public.circle_channels cc
  where cc.conversation_id = new.conversation_id;

  -- A forum channel's own conversation takes no messages: they go into
  -- its posts (threads).
  if channel.kind = 'forum' then
    raise exception 'Messages in a forum channel go into its posts'
      using errcode = '42501';
  end if;

  if channel.id is null
    or channel.slowmode_seconds <= 0
    or public.circle_channel_has_permission(
      channel.id,
      new.sender_id,
      'manage_messages'
    )
  then
    return new;
  end if;

  -- One send per member and channel at a time, so two quick sends cannot
  -- both pass.
  perform pg_advisory_xact_lock(
    hashtextextended(new.conversation_id::text || ':' || new.sender_id::text, 0)
  );

  select max(m.created_at) into last_sent_at
  from public.messages m
  where m.conversation_id = new.conversation_id
    and m.sender_id = new.sender_id
    and m.type <> 'system';

  if last_sent_at is not null
    and last_sent_at + make_interval(secs => channel.slowmode_seconds) > now()
  then
    remaining_seconds := greatest(
      1,
      ceil(
        extract(
          epoch from
            last_sent_at + make_interval(secs => channel.slowmode_seconds) - now()
        )
      )::integer
    );
    raise exception 'Slowmode is enabled. Try again in % seconds.', remaining_seconds
      using errcode = 'P0001',
        detail = format('slowmode_remaining_seconds=%s', remaining_seconds);
  end if;

  return new;
end;
$$;

revoke execute on function public.check_channel_message_send() from public;
revoke execute on function public.check_channel_message_send() from anon;
revoke execute on function public.check_channel_message_send() from authenticated;

-- Same as 202610130014_channel_permission_overwrites, but forum channels take
-- posts (create_forum_post), not threads.
create or replace function public.create_thread(
  parent_conversation_id uuid,
  root_message_id uuid default null,
  title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  parent_type text;
  root_message public.messages%rowtype;
  existing_thread public.conversation_threads%rowtype;
  created_thread public.conversation_threads%rowtype;
  created_conversation_id uuid;
  normalized_title text := nullif(
    regexp_replace(btrim(coalesce(create_thread.title, '')), '\s+', ' ', 'g'),
    ''
  );
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select c.type
  into parent_type
  from public.conversations c
  where c.id = create_thread.parent_conversation_id;

  if parent_type is null
    or not public.is_current_user_conversation_member(
      create_thread.parent_conversation_id
    )
  then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if parent_type not in ('channel', 'group') then
    raise exception 'Threads can only start in channels and groups'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.circle_channels cc
    where cc.conversation_id = create_thread.parent_conversation_id
      and cc.kind = 'forum'
  ) then
    raise exception 'Forum channels take posts, not threads'
      using errcode = '22023';
  end if;

  if not public.user_has_conversation_channel_permission(
    create_thread.parent_conversation_id,
    current_user_id,
    'send_messages'
  ) then
    raise exception 'You do not have permission to send messages in this channel'
      using errcode = '42501';
  end if;

  if create_thread.root_message_id is not null then
    -- Lock the root so concurrent calls agree on a single thread.
    select m.*
    into root_message
    from public.messages m
    where m.id = create_thread.root_message_id
      and m.conversation_id = create_thread.parent_conversation_id
    for update;

    if root_message.id is null then
      raise exception 'Root message not found in this conversation'
        using errcode = '22023';
    end if;

    select ct.*
    into existing_thread
    from public.conversation_threads ct
    where ct.root_message_id = root_message.id;

    if existing_thread.id is not null then
      return public.thread_payload(existing_thread);
    end if;

    if root_message.recalled_at is not null or root_message.type = 'system' then
      raise exception 'Threads cannot start from this message'
        using errcode = '22023';
    end if;

    normalized_title := coalesce(
      normalized_title,
      nullif(
        left(regexp_replace(btrim(root_message.body), '\s+', ' ', 'g'), 40),
        ''
      ),
      case root_message.type
        when 'image' then 'Image'
        when 'voice' then 'Voice message'
        else 'Thread'
      end
    );
  end if;

  if normalized_title is null then
    raise exception 'Thread title is required' using errcode = '22023';
  end if;

  if char_length(normalized_title) > 100 then
    raise exception 'Thread title must be at most 100 characters'
      using errcode = '22023';
  end if;

  insert into public.conversations (type, title)
  values ('thread', normalized_title)
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, 'member'
  from public.conversation_members cm
  where cm.conversation_id = create_thread.parent_conversation_id
  on conflict do nothing;

  insert into public.conversation_threads (
    parent_conversation_id,
    root_message_id,
    conversation_id,
    title,
    created_by
  )
  values (
    create_thread.parent_conversation_id,
    create_thread.root_message_id,
    created_conversation_id,
    normalized_title,
    current_user_id
  )
  returning * into created_thread;

  return public.thread_payload(created_thread);
end;
$$;

-- Same as 202610130019_channel_management, plus each forum's tags.
create or replace function public.get_circle_detail(target_circle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'circle',
    jsonb_build_object(
      'id', c.id,
      'name', c.name,
      'avatar_url', c.avatar_url,
      'owner_id', c.owner_id,
      'created_at', c.created_at,
      'updated_at', c.updated_at,
      'current_user_role', current_member.role,
      'current_user_permissions', caller.permissions
    ),
    'roles',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'name', r.name,
          'color', r.color,
          'position', r.position,
          'permissions', r.permissions,
          'hoist', r.hoist,
          'is_default', r.is_default,
          'member_count', case
            when r.is_default then (
              select count(*)
              from public.circle_members cm
              where cm.circle_id = c.id
            )
            else (
              select count(*)
              from public.circle_member_roles mr
              where mr.role_id = r.id
            )
          end
        )
        order by r.position desc
      )
      from public.circle_roles r
      where r.circle_id = c.id
    ), '[]'::jsonb),
    'members',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role', cm.role,
          'nickname', cm.nickname,
          'is_current_user', cm.user_id = auth.uid(),
          'created_at', cm.created_at,
          'role_ids', coalesce((
            select jsonb_agg(r.id order by r.position desc)
            from public.circle_member_roles mr
            join public.circle_roles r on r.id = mr.role_id
            where mr.circle_id = cm.circle_id
              and mr.user_id = cm.user_id
          ), '[]'::jsonb),
          'profile',
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.display_name,
            'avatar_url', p.avatar_url,
            'bio', p.bio,
            'created_at', p.created_at,
            'updated_at', p.updated_at,
            'custom_status', public.custom_status(p)
          )
        )
        order by
          case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,
          coalesce(cm.nickname, p.display_name)
      )
      from public.circle_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.circle_id = c.id
    ), '[]'::jsonb),
    'channels',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cc.id,
          'circle_id', cc.circle_id,
          'conversation_id', cc.conversation_id,
          'name', cc.name,
          'position', cc.position,
          'category_id', cc.category_id,
          'created_by', cc.created_by,
          'current_user_permissions', channel_access.permissions,
          'is_private', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('view_channel') <> 0,
            false
          ),
          'is_read_only', coalesce(
            everyone_overwrite.deny
              & public.circle_permission_bit('send_messages') <> 0,
            false
          ),
          'slowmode_seconds', cc.slowmode_seconds,
          'topic', cc.topic,
          'kind', cc.kind,
          'tags', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', ft.id,
                'channel_id', ft.channel_id,
                'name', ft.name,
                'emoji', ft.emoji,
                'position', ft.position
              )
              order by ft.position, ft.created_at
            )
            from public.forum_tags ft
            where ft.channel_id = cc.id
          ), '[]'::jsonb)
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      cross join lateral (
        select public.circle_channel_permissions(cc.id, auth.uid()) as permissions
      ) channel_access
      left join lateral (
        select o.deny
        from public.circle_channel_overwrites o
        join public.circle_roles r on r.id = o.role_id
        where o.channel_id = cc.id
          and r.is_default
      ) everyone_overwrite on true
      where cc.circle_id = c.id
        and channel_access.permissions
          & public.circle_permission_bit('view_channel') <> 0
    ), '[]'::jsonb),
    'categories',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', ccc.id,
          'circle_id', ccc.circle_id,
          'name', ccc.name,
          'position', ccc.position,
          'created_at', ccc.created_at
        )
        order by ccc.position, ccc.created_at
      )
      from public.circle_channel_categories ccc
      where ccc.circle_id = c.id
    ), '[]'::jsonb),
    'posts',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', cp.id,
          'circle_id', cp.circle_id,
          'author_id', cp.author_id,
          'author',
          jsonb_build_object(
            'id', author.id,
            'username', author.username,
            'display_name', author.display_name,
            'avatar_url', author.avatar_url,
            'bio', author.bio,
            'created_at', author.created_at,
            'updated_at', author.updated_at
          ),
          'body', cp.body,
          'attachment', cp.attachment,
          'created_at', cp.created_at,
          'updated_at', cp.updated_at,
          'is_own_post', cp.author_id = auth.uid(),
          'can_manage_post',
          cp.author_id = auth.uid()
            or caller.permissions
              & public.circle_permission_bit('manage_messages') <> 0,
          'like_count', (
            select count(*)
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
          ),
          'comment_count', (
            select count(*)
            from public.circle_post_comments cpc
            where cpc.post_id = cp.id
          ),
          'liked_by_current_user', exists (
            select 1
            from public.circle_post_likes cpl
            where cpl.post_id = cp.id
              and cpl.user_id = auth.uid()
          ),
          'comments',
          coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', cpc.id,
                'post_id', cpc.post_id,
                'author_id', cpc.author_id,
                'body', cpc.body,
                'created_at', cpc.created_at,
                'updated_at', cpc.updated_at,
                'is_own_comment', cpc.author_id = auth.uid(),
                'author',
                jsonb_build_object(
                  'id', comment_author.id,
                  'username', comment_author.username,
                  'display_name', comment_author.display_name,
                  'avatar_url', comment_author.avatar_url,
                  'bio', comment_author.bio,
                  'created_at', comment_author.created_at,
                  'updated_at', comment_author.updated_at
                )
              )
              order by cpc.created_at
            )
            from public.circle_post_comments cpc
            join public.profiles comment_author on comment_author.id = cpc.author_id
            where cpc.post_id = cp.id
              and cpc.deleted_at is null
          ), '[]'::jsonb)
        )
        order by cp.created_at desc
      )
      from public.circle_posts cp
      join public.profiles author on author.id = cp.author_id
      where cp.circle_id = c.id
        and cp.deleted_at is null
    ), '[]'::jsonb)
  )
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  cross join lateral (
    select public.circle_member_permissions(c.id, auth.uid()) as permissions
  ) caller
  where c.id = target_circle_id;
$$;

revoke execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb) from public;
revoke execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb) from anon;
revoke execute on function public.list_forum_posts(uuid, text, uuid, timestamptz, uuid, integer) from public;
revoke execute on function public.list_forum_posts(uuid, text, uuid, timestamptz, uuid, integer) from anon;
revoke execute on function public.set_forum_post_tags(uuid, uuid[]) from public;
revoke execute on function public.set_forum_post_tags(uuid, uuid[]) from anon;
revoke execute on function public.pin_forum_post(uuid, boolean) from public;
revoke execute on function public.pin_forum_post(uuid, boolean) from anon;
revoke execute on function public.create_forum_tag(uuid, text, text) from public;
revoke execute on function public.create_forum_tag(uuid, text, text) from anon;
revoke execute on function public.update_forum_tag(uuid, text, text) from public;
revoke execute on function public.update_forum_tag(uuid, text, text) from anon;
revoke execute on function public.delete_forum_tag(uuid) from public;
revoke execute on function public.delete_forum_tag(uuid) from anon;
revoke execute on function public.reorder_forum_tags(uuid, uuid[]) from public;
revoke execute on function public.reorder_forum_tags(uuid, uuid[]) from anon;

grant select on public.forum_tags to authenticated;
grant select on public.thread_tags to authenticated;
grant execute on function public.create_forum_post(uuid, text, text, uuid[], jsonb) to authenticated;
grant execute on function public.list_forum_posts(uuid, text, uuid, timestamptz, uuid, integer) to authenticated;
grant execute on function public.set_forum_post_tags(uuid, uuid[]) to authenticated;
grant execute on function public.pin_forum_post(uuid, boolean) to authenticated;
grant execute on function public.create_forum_tag(uuid, text, text) to authenticated;
grant execute on function public.update_forum_tag(uuid, text, text) to authenticated;
grant execute on function public.delete_forum_tag(uuid) to authenticated;
grant execute on function public.reorder_forum_tags(uuid, uuid[]) to authenticated;
grant execute on function public.create_circle_channel(uuid, text, uuid, text) to authenticated;
grant execute on function public.create_thread(uuid, uuid, text) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
