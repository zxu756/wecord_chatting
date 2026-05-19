alter table public.conversations
  add column if not exists announcement_updated_at timestamptz,
  add column if not exists announcement_updated_by uuid references public.profiles(id) on delete set null;

create table if not exists public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  avatar_url text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circles_name_length check (char_length(trim(name)) between 1 and 80)
);

create table if not exists public.circle_members (
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id),
  constraint circle_members_role_check check (role in ('owner', 'admin', 'member'))
);

create table if not exists public.circle_channels (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_channels_name_length check (char_length(trim(name)) between 1 and 48),
  constraint circle_channels_conversation_unique unique (conversation_id)
);

create table if not exists public.circle_posts (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '',
  attachment jsonb,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_posts_content_check check (
    char_length(trim(body)) > 0 or attachment is not null
  )
);

create table if not exists public.circle_post_likes (
  post_id uuid not null references public.circle_posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.circle_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.circle_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint circle_post_comments_body_length check (char_length(trim(body)) between 1 and 1000)
);

create index if not exists circles_owner_idx
  on public.circles (owner_id, created_at desc);
create index if not exists circle_members_user_idx
  on public.circle_members (user_id, created_at desc);
create index if not exists circle_channels_circle_position_idx
  on public.circle_channels (circle_id, position, created_at);
create index if not exists circle_posts_circle_created_idx
  on public.circle_posts (circle_id, created_at desc);
create index if not exists circle_post_likes_user_idx
  on public.circle_post_likes (user_id, created_at desc);
create index if not exists circle_post_comments_post_created_idx
  on public.circle_post_comments (post_id, created_at);

alter table public.reports
  add column if not exists target_post_id uuid references public.circle_posts(id) on delete set null;

create index if not exists reports_target_post_created_idx
  on public.reports (target_post_id, created_at desc)
  where target_post_id is not null;

alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.circle_channels enable row level security;
alter table public.circle_posts enable row level security;
alter table public.circle_post_likes enable row level security;
alter table public.circle_post_comments enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circles'
  ) then
    alter publication supabase_realtime add table public.circles;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_members'
  ) then
    alter publication supabase_realtime add table public.circle_members;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_channels'
  ) then
    alter publication supabase_realtime add table public.circle_channels;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_posts'
  ) then
    alter publication supabase_realtime add table public.circle_posts;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_post_likes'
  ) then
    alter publication supabase_realtime add table public.circle_post_likes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_post_comments'
  ) then
    alter publication supabase_realtime add table public.circle_post_comments;
  end if;
end $$;

create or replace function public.is_current_user_circle_member(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = auth.uid()
  );
$$;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do update
set public = false;

drop policy if exists chat_media_select_authenticated on storage.objects;
create policy chat_media_select_authenticated
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'chat-media'
    and public.is_current_user_circle_member(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop policy if exists chat_media_insert_authenticated on storage.objects;
create policy chat_media_insert_authenticated
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'chat-media'
    and public.is_current_user_circle_member(
      ((storage.foldername(name))[1])::uuid
    )
  );

drop trigger if exists circles_set_updated_at on public.circles;
create trigger circles_set_updated_at
  before update on public.circles
  for each row execute function public.set_updated_at();

drop trigger if exists circle_channels_set_updated_at on public.circle_channels;
create trigger circle_channels_set_updated_at
  before update on public.circle_channels
  for each row execute function public.set_updated_at();

drop trigger if exists circle_posts_set_updated_at on public.circle_posts;
create trigger circle_posts_set_updated_at
  before update on public.circle_posts
  for each row execute function public.set_updated_at();

drop trigger if exists circle_post_comments_set_updated_at on public.circle_post_comments;
create trigger circle_post_comments_set_updated_at
  before update on public.circle_post_comments
  for each row execute function public.set_updated_at();

create or replace function public.is_current_user_circle_member(target_circle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = auth.uid()
  );
$$;

create or replace function public.current_user_circle_role(target_circle_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select cm.role
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = auth.uid()
  limit 1;
$$;

drop policy if exists circles_select_member on public.circles;
create policy circles_select_member
  on public.circles for select
  to authenticated
  using (public.is_current_user_circle_member(id));

drop policy if exists circle_members_select_member on public.circle_members;
create policy circle_members_select_member
  on public.circle_members for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

drop policy if exists circle_channels_select_member on public.circle_channels;
create policy circle_channels_select_member
  on public.circle_channels for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

drop policy if exists circle_posts_select_member on public.circle_posts;
create policy circle_posts_select_member
  on public.circle_posts for select
  to authenticated
  using (
    deleted_at is null
    and public.is_current_user_circle_member(circle_id)
  );

drop policy if exists circle_post_likes_select_member on public.circle_post_likes;
create policy circle_post_likes_select_member
  on public.circle_post_likes for select
  to authenticated
  using (
    exists (
      select 1
      from public.circle_posts cp
      where cp.id = post_id
        and public.is_current_user_circle_member(cp.circle_id)
    )
  );

drop policy if exists circle_post_comments_select_member on public.circle_post_comments;
create policy circle_post_comments_select_member
  on public.circle_post_comments for select
  to authenticated
  using (
    circle_post_comments.deleted_at is null
    and exists (
      select 1
      from public.circle_posts cp
      where cp.id = post_id
        and cp.deleted_at is null
        and public.is_current_user_circle_member(cp.circle_id)
    )
  );

create or replace function public.create_circle(
  circle_name text,
  member_ids uuid[] default array[]::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(circle_name, ''));
  created_circle_id uuid;
  created_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 80 then
    raise exception 'Circle name must be between 1 and 80 characters'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where candidate.member_id is null
      or candidate.member_id = current_user_id
      or not exists (
        select 1
        from public.profiles p
        where p.id = candidate.member_id
      )
      or not exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(current_user_id, candidate.member_id)
          and f.user_high_id = greatest(current_user_id, candidate.member_id)
      )
      or public.are_users_blocked(current_user_id, candidate.member_id)
  ) then
    raise exception 'Invalid circle invite members' using errcode = '42501';
  end if;

  insert into public.circles (name, owner_id)
  values (trimmed_name, current_user_id)
  returning id into created_circle_id;

  insert into public.circle_members (circle_id, user_id, role)
  values (created_circle_id, current_user_id, 'owner');

  insert into public.circle_members (circle_id, user_id, role)
  select created_circle_id, invited.member_id, 'member'
  from (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ) invited
  where exists (
    select 1
    from public.friendships f
    where f.user_low_id = least(current_user_id, invited.member_id)
      and f.user_high_id = greatest(current_user_id, invited.member_id)
  )
    and not public.are_users_blocked(current_user_id, invited.member_id)
  on conflict do nothing;

  insert into public.conversations (type, title)
  values ('channel', 'general')
  returning id into created_conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role)
  select created_conversation_id, cm.user_id, cm.role
  from public.circle_members cm
  where cm.circle_id = created_circle_id
  on conflict do nothing;

  insert into public.circle_channels (
    circle_id,
    conversation_id,
    name,
    position,
    created_by
  )
  values (
    created_circle_id,
    created_conversation_id,
    'general',
    0,
    current_user_id
  );

  return created_circle_id;
end;
$$;

create or replace function public.list_circle_summaries()
returns table (
  id uuid,
  name text,
  avatar_url text,
  member_count bigint,
  channel_count bigint,
  latest_activity_at timestamptz,
  current_user_role text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.name,
    c.avatar_url,
    count(distinct all_members.user_id) as member_count,
    count(distinct cc.id) as channel_count,
    greatest(
      c.updated_at,
      coalesce(max(cp.created_at), c.updated_at),
      coalesce(max(ch_conversation.last_message_at), c.updated_at)
    ) as latest_activity_at,
    current_member.role as current_user_role
  from public.circles c
  join public.circle_members current_member
    on current_member.circle_id = c.id
    and current_member.user_id = auth.uid()
  left join public.circle_members all_members on all_members.circle_id = c.id
  left join public.circle_channels cc on cc.circle_id = c.id
  left join public.conversations ch_conversation
    on ch_conversation.id = cc.conversation_id
  left join public.circle_posts cp on cp.circle_id = c.id
  group by c.id, c.name, c.avatar_url, c.updated_at, current_member.role
  order by latest_activity_at desc, c.created_at desc;
$$;

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
      'current_user_role', current_member.role
    ),
    'members',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'role', cm.role,
          'created_at', cm.created_at,
          'profile',
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.display_name,
            'avatar_url', p.avatar_url,
            'bio', p.bio,
            'created_at', p.created_at,
            'updated_at', p.updated_at
          )
        )
        order by
          case cm.role when 'owner' then 0 when 'admin' then 1 else 2 end,
          p.display_name
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
          'created_by', cc.created_by
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      where cc.circle_id = c.id
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
          cp.author_id = auth.uid() or current_member.role in ('owner', 'admin'),
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
  where c.id = target_circle_id;
$$;

create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(channel_name, ''));
  caller_role text;
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

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if caller_role not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can create channels'
      using errcode = '42501';
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
    created_by
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
    current_user_id
  )
  returning id into created_channel_id;

  return created_channel_id;
end;
$$;

create or replace function public.invite_circle_members(
  target_circle_id uuid,
  member_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if caller_role not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can invite members'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where candidate.member_id is null
      or candidate.member_id = current_user_id
      or not exists (
        select 1
        from public.profiles p
        where p.id = candidate.member_id
      )
      or not exists (
        select 1
        from public.friendships f
        where f.user_low_id = least(current_user_id, candidate.member_id)
          and f.user_high_id = greatest(current_user_id, candidate.member_id)
      )
      or public.are_users_blocked(current_user_id, candidate.member_id)
  ) then
    raise exception 'Invalid circle invite members' using errcode = '42501';
  end if;

  if exists (
    select 1
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    join public.circle_members cm
      on cm.circle_id = target_circle_id
      and cm.user_id = candidate.member_id
  ) then
    raise exception 'User is already a circle member' using errcode = '23505';
  end if;

  with invited as (
    select distinct member_id
    from unnest(coalesce(member_ids, array[]::uuid[])) as candidate(member_id)
    where member_id is not null
      and member_id <> current_user_id
  ),
  allowed as (
    select invited.member_id
    from invited
    where exists (
      select 1
      from public.friendships f
      where f.user_low_id = least(current_user_id, invited.member_id)
        and f.user_high_id = greatest(current_user_id, invited.member_id)
    )
      and not public.are_users_blocked(current_user_id, invited.member_id)
  ),
  inserted as (
    insert into public.circle_members (circle_id, user_id, role)
    select target_circle_id, allowed.member_id, 'member'
    from allowed
    on conflict do nothing
    returning user_id
  )
  insert into public.conversation_members (conversation_id, user_id, role)
  select cc.conversation_id, inserted.user_id, 'member'
  from inserted
  cross join public.circle_channels cc
  where cc.circle_id = target_circle_id
  on conflict do nothing;
end;
$$;

create or replace function public.create_circle_post(
  target_circle_id uuid,
  body text,
  attachment jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  created_post_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 and attachment is null then
    raise exception 'Post body or attachment is required' using errcode = '22023';
  end if;

  insert into public.circle_posts (circle_id, author_id, body, attachment)
  values (target_circle_id, current_user_id, trimmed_body, attachment)
  returning id into created_post_id;

  return created_post_id;
end;
$$;

create or replace function public.toggle_circle_post_like(
  target_post_id uuid,
  liked boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_circle_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select cp.circle_id into target_circle_id
  from public.circle_posts cp
  where cp.id = target_post_id
    and cp.deleted_at is null;

  if target_circle_id is null
    or not public.is_current_user_circle_member(target_circle_id)
  then
    raise exception 'Post not found or caller is not a circle member'
      using errcode = '42501';
  end if;

  if liked then
    insert into public.circle_post_likes (post_id, user_id)
    values (target_post_id, current_user_id)
    on conflict do nothing;
  else
    delete from public.circle_post_likes
    where post_id = target_post_id
      and user_id = current_user_id;
  end if;
end;
$$;

create or replace function public.create_circle_post_comment(
  target_post_id uuid,
  body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_body text := trim(coalesce(body, ''));
  target_circle_id uuid;
  created_comment_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_body) = 0 or char_length(trimmed_body) > 1000 then
    raise exception 'Comment body must be between 1 and 1000 characters'
      using errcode = '22023';
  end if;

  select cp.circle_id into target_circle_id
  from public.circle_posts cp
  where cp.id = target_post_id
    and cp.deleted_at is null;

  if target_circle_id is null
    or not public.is_current_user_circle_member(target_circle_id)
  then
    raise exception 'Post not found or caller is not a circle member'
      using errcode = '42501';
  end if;

  insert into public.circle_post_comments (post_id, author_id, body)
  values (target_post_id, current_user_id, trimmed_body)
  returning id into created_comment_id;

  return created_comment_id;
end;
$$;

create or replace function public.delete_circle_post(target_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts
  where id = target_post_id
    and deleted_at is null;

  if target_post.id is null then
    raise exception 'Post not found' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_post.circle_id) into caller_role;

  if target_post.author_id <> current_user_id
    and caller_role not in ('owner', 'admin')
  then
    raise exception 'Caller cannot delete this post' using errcode = '42501';
  end if;

  update public.circle_posts
  set deleted_at = now()
  where id = target_post_id;
end;
$$;

create or replace function public.report_circle_post(
  target_post_id uuid,
  report_reason text,
  report_details text default ''
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_post public.circle_posts%rowtype;
  created_report_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into target_post
  from public.circle_posts
  where id = target_post_id
    and deleted_at is null;

  if target_post.id is null
    or not public.is_current_user_circle_member(target_post.circle_id)
  then
    raise exception 'Post not found or caller is not a circle member'
      using errcode = '42501';
  end if;

  if target_post.author_id = current_user_id then
    raise exception 'Cannot report your own post' using errcode = '22023';
  end if;

  insert into public.reports (
    reporter_id,
    target_user_id,
    target_post_id,
    reason,
    details
  )
  values (
    current_user_id,
    target_post.author_id,
    target_post_id,
    report_reason,
    left(coalesce(report_details, ''), 1000)
  )
  returning id into created_report_id;

  return created_report_id;
end;
$$;

drop function if exists public.update_group_profile(uuid, text, text, text);

create or replace function public.update_group_profile(
  target_conversation_id uuid,
  group_title text,
  avatar_url text,
  announcement text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  trimmed_title text := trim(coalesce(group_title, ''));
  updated_conversation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_title) = 0 then
    raise exception 'Group title is required' using errcode = '22023';
  end if;

  update public.conversations c
  set
    title = trimmed_title,
    avatar_url = update_group_profile.avatar_url,
    announcement_updated_at = case
      when coalesce(c.announcement, '') is distinct from coalesce(update_group_profile.announcement, '')
        then now()
      else c.announcement_updated_at
    end,
    announcement_updated_by = case
      when coalesce(c.announcement, '') is distinct from coalesce(update_group_profile.announcement, '')
        then auth.uid()
      else c.announcement_updated_by
    end,
    announcement = coalesce(update_group_profile.announcement, '')
  where c.id = target_conversation_id
    and c.type = 'group'
    and exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = c.id
        and cm.user_id = auth.uid()
        and cm.role in ('owner', 'admin')
    )
  returning c.id into updated_conversation_id;

  if updated_conversation_id is null then
    raise exception 'Group conversation not found or cannot be updated'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.search_discovery(search_query text)
returns table (
  result_type text,
  id uuid,
  title text,
  subtitle text,
  avatar_url text,
  conversation_id uuid,
  circle_id uuid,
  channel_id uuid,
  rank real
)
language sql
stable
security definer
set search_path = public
as $$
  with query_input as (
    select trim(coalesce(search_query, '')) as q
  ),
  friend_results as (
    select
      'contact'::text as result_type,
      p.id,
      coalesce(ca.alias, p.display_name) as title,
      p.username as subtitle,
      p.avatar_url,
      null::uuid as conversation_id,
      null::uuid as circle_id,
      null::uuid as channel_id,
      1.0::real as rank
    from query_input qi
    join public.friendships f
      on auth.uid() in (f.user_low_id, f.user_high_id)
    join public.profiles p
      on p.id = case
        when f.user_low_id = auth.uid() then f.user_high_id
        else f.user_low_id
      end
    left join public.contact_aliases ca
      on ca.owner_id = auth.uid()
      and ca.friend_id = p.id
    where qi.q <> ''
      and (
        p.display_name ilike '%' || qi.q || '%'
        or p.username ilike '%' || qi.q || '%'
        or ca.alias ilike '%' || qi.q || '%'
      )
  ),
  group_results as (
    select
      'group'::text as result_type,
      c.id,
      c.title,
      c.announcement as subtitle,
      c.avatar_url,
      c.id as conversation_id,
      null::uuid as circle_id,
      null::uuid as channel_id,
      0.8::real as rank
    from query_input qi
    join public.conversation_members cm
      on cm.user_id = auth.uid()
    join public.conversations c
      on c.id = cm.conversation_id
      and c.type = 'group'
    where qi.q <> ''
      and coalesce(c.title, '') ilike '%' || qi.q || '%'
  ),
  circle_results as (
    select
      'circle'::text as result_type,
      c.id,
      c.name as title,
      count(all_members.user_id)::text || ' members' as subtitle,
      c.avatar_url,
      null::uuid as conversation_id,
      c.id as circle_id,
      null::uuid as channel_id,
      0.7::real as rank
    from query_input qi
    join public.circle_members current_member
      on current_member.user_id = auth.uid()
    join public.circles c
      on c.id = current_member.circle_id
    left join public.circle_members all_members on all_members.circle_id = c.id
    where qi.q <> ''
      and c.name ilike '%' || qi.q || '%'
    group by c.id, c.name, c.avatar_url
  ),
  channel_results as (
    select
      'circle_channel'::text as result_type,
      cc.id,
      cc.name as title,
      c.name as subtitle,
      c.avatar_url,
      cc.conversation_id,
      cc.circle_id,
      cc.id as channel_id,
      0.65::real as rank
    from query_input qi
    join public.circle_members current_member
      on current_member.user_id = auth.uid()
    join public.circle_channels cc
      on cc.circle_id = current_member.circle_id
    join public.circles c
      on c.id = cc.circle_id
    where qi.q <> ''
      and cc.name ilike '%' || qi.q || '%'
  ),
  message_results as (
    select
      'message'::text as result_type,
      m.id,
      left(m.body, 80) as title,
      coalesce(c.title, sender.display_name) as subtitle,
      sender.avatar_url,
      m.conversation_id,
      cc.circle_id,
      cc.id as channel_id,
      0.5::real as rank
    from query_input qi
    join public.conversation_members cm
      on cm.user_id = auth.uid()
    join public.messages m
      on m.conversation_id = cm.conversation_id
      and m.recalled_at is null
    join public.conversations c on c.id = m.conversation_id
    join public.profiles sender on sender.id = m.sender_id
    left join public.circle_channels cc on cc.conversation_id = m.conversation_id
    where qi.q <> ''
      and m.body ilike '%' || qi.q || '%'
  )
  select * from friend_results
  union all
  select * from group_results
  union all
  select * from circle_results
  union all
  select * from channel_results
  union all
  select * from message_results
  order by rank desc, title;
$$;

create or replace function public.list_conversation_media(
  target_conversation_id uuid
)
returns table (
  message_id uuid,
  conversation_id uuid,
  sender_id uuid,
  sender_name text,
  type text,
  body text,
  attachment jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id as message_id,
    m.conversation_id,
    m.sender_id,
    p.display_name as sender_name,
    m.type,
    m.body,
    m.attachment,
    m.created_at
  from public.messages m
  join public.profiles p on p.id = m.sender_id
  where m.conversation_id = target_conversation_id
    and public.is_current_user_conversation_member(target_conversation_id)
    and m.type in ('image', 'voice', 'file')
    and m.recalled_at is null
  order by m.created_at desc;
$$;
