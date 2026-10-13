-- Channel categories. Channels without a category are listed first, then
-- each category with its channels. Positions of categories and channels are
-- only written by the RPCs below; reorder_circle_channels replaces the whole
-- layout of a circle in one statement so clients never see half a reorder.
create table if not exists public.circle_channel_categories (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  constraint circle_channel_categories_name_length check (
    char_length(trim(name)) between 1 and 32
  )
);

create index if not exists circle_channel_categories_circle_position_idx
  on public.circle_channel_categories (circle_id, position, created_at);

alter table public.circle_channels
  add column if not exists category_id uuid
    references public.circle_channel_categories(id) on delete set null;

create index if not exists circle_channels_category_idx
  on public.circle_channels (category_id)
  where category_id is not null;

-- Realtime matches DELETE events against the old row, so keep circle_id in
-- it to let an open circle filter category removals.
alter table public.circle_channel_categories replica identity full;

alter table public.circle_channel_categories enable row level security;

drop policy if exists circle_channel_categories_select_member
  on public.circle_channel_categories;
create policy circle_channel_categories_select_member
  on public.circle_channel_categories for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'circle_channel_categories'
  ) then
    alter publication supabase_realtime add table public.circle_channel_categories;
  end if;
end $$;

create or replace function public.create_channel_category(
  target_circle_id uuid,
  category_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(category_name, ''));
  caller_role text;
  created_category_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 32 then
    raise exception 'Category name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can manage categories'
      using errcode = '42501';
  end if;

  -- Serialises layout changes of one circle.
  perform 1 from public.circles where id = target_circle_id for no key update;

  insert into public.circle_channel_categories (circle_id, name, position)
  values (
    target_circle_id,
    trimmed_name,
    coalesce((
      select max(position) + 1
      from public.circle_channel_categories
      where circle_id = target_circle_id
    ), 0)
  )
  returning id into created_category_id;

  return created_category_id;
end;
$$;

create or replace function public.rename_channel_category(
  target_category_id uuid,
  category_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := trim(coalesce(category_name, ''));
  target_circle_id uuid;
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(trimmed_name) = 0 or char_length(trimmed_name) > 32 then
    raise exception 'Category name must be between 1 and 32 characters'
      using errcode = '22023';
  end if;

  select ccc.circle_id into target_circle_id
  from public.circle_channel_categories ccc
  where ccc.id = target_category_id;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if target_circle_id is null or coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can manage categories'
      using errcode = '42501';
  end if;

  update public.circle_channel_categories
  set name = trimmed_name
  where id = target_category_id;
end;
$$;

create or replace function public.delete_channel_category(target_category_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  target_circle_id uuid;
  caller_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select ccc.circle_id into target_circle_id
  from public.circle_channel_categories ccc
  where ccc.id = target_category_id;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if target_circle_id is null or coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can manage categories'
      using errcode = '42501';
  end if;

  perform 1 from public.circles where id = target_circle_id for no key update;

  -- The foreign key would do this too; updating first keeps updated_at
  -- honest and notifies realtime listeners of circle_channels.
  update public.circle_channels
  set category_id = null,
      updated_at = now()
  where category_id = target_category_id;

  delete from public.circle_channel_categories
  where id = target_category_id;
end;
$$;

-- layout = {"categories": [category ids in order],
--           "channels": [{"id": channel id, "category_id": id or null}, ...]}
-- Every category and channel of the circle must appear exactly once.
create or replace function public.reorder_circle_channels(
  target_circle_id uuid,
  layout jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  caller_role text;
  category_ids uuid[];
  channel_ids uuid[];
  channel_category_ids uuid[];
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can reorder channels'
      using errcode = '42501';
  end if;

  if jsonb_typeof(layout) is distinct from 'object'
    or jsonb_typeof(layout -> 'categories') is distinct from 'array'
    or jsonb_typeof(layout -> 'channels') is distinct from 'array'
    or exists (
      select 1
      from jsonb_array_elements(layout -> 'categories') as item(value)
      where jsonb_typeof(item.value) <> 'string'
    )
    or exists (
      select 1
      from jsonb_array_elements(layout -> 'channels') as item(value)
      where jsonb_typeof(item.value) <> 'object'
        or jsonb_typeof(item.value -> 'id') is distinct from 'string'
        or coalesce(jsonb_typeof(item.value -> 'category_id'), 'null')
          not in ('string', 'null')
    )
  then
    raise exception 'Invalid channel layout' using errcode = '22023';
  end if;

  begin
    select coalesce(array_agg((item.value #>> '{}')::uuid order by item.ordinality), '{}')
    into category_ids
    from jsonb_array_elements(layout -> 'categories') with ordinality as item(value, ordinality);

    select
      coalesce(array_agg((item.value ->> 'id')::uuid order by item.ordinality), '{}'),
      coalesce(array_agg((item.value ->> 'category_id')::uuid order by item.ordinality), '{}')
    into channel_ids, channel_category_ids
    from jsonb_array_elements(layout -> 'channels') with ordinality as item(value, ordinality);
  exception
    when invalid_text_representation then
      raise exception 'Invalid channel layout' using errcode = '22023';
  end;

  -- Lock the circle so concurrent creates and reorders apply one at a time.
  perform 1 from public.circles where id = target_circle_id for no key update;

  if cardinality(category_ids) <> (
      select count(distinct category_id) from unnest(category_ids) as ids(category_id)
    )
    or (
      select count(*)
      from public.circle_channel_categories ccc
      where ccc.circle_id = target_circle_id
    ) <> cardinality(category_ids)
    or exists (
      select 1
      from unnest(category_ids) as ids(category_id)
      where not exists (
        select 1
        from public.circle_channel_categories ccc
        where ccc.id = ids.category_id
          and ccc.circle_id = target_circle_id
      )
    )
  then
    raise exception 'Layout must list every category of the circle once'
      using errcode = '22023';
  end if;

  if cardinality(channel_ids) <> (
      select count(distinct channel_id) from unnest(channel_ids) as ids(channel_id)
    )
    or (
      select count(*)
      from public.circle_channels cc
      where cc.circle_id = target_circle_id
    ) <> cardinality(channel_ids)
    or exists (
      select 1
      from unnest(channel_ids) as ids(channel_id)
      where not exists (
        select 1
        from public.circle_channels cc
        where cc.id = ids.channel_id
          and cc.circle_id = target_circle_id
      )
    )
  then
    raise exception 'Layout must list every channel of the circle once'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(channel_category_ids) as ids(category_id)
    where ids.category_id is not null
      and not (ids.category_id = any(category_ids))
  ) then
    raise exception 'Channels can only be placed in categories of the circle'
      using errcode = '22023';
  end if;

  update public.circle_channel_categories ccc
  set position = ordered.ordinality - 1
  from unnest(category_ids) with ordinality as ordered(category_id, ordinality)
  where ccc.id = ordered.category_id
    and ccc.position is distinct from ordered.ordinality - 1;

  update public.circle_channels cc
  set position = ordered.ordinality - 1,
      category_id = ordered.category_id,
      updated_at = now()
  from unnest(channel_ids, channel_category_ids)
    with ordinality as ordered(channel_id, category_id, ordinality)
  where cc.id = ordered.channel_id
    and (
      cc.position is distinct from ordered.ordinality - 1
      or cc.category_id is distinct from ordered.category_id
    );
end;
$$;

-- Same as 202605190003_community_discovery_v1, plus an optional category.
-- The two-argument version is dropped so PostgREST resolves existing callers
-- (which omit target_category_id) to this function without ambiguity. It
-- also now refuses callers outside the circle (a null role used to slip past
-- the role check).
drop function if exists public.create_circle_channel(uuid, text);

create or replace function public.create_circle_channel(
  target_circle_id uuid,
  channel_name text,
  target_category_id uuid default null
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

  if coalesce(caller_role, '') not in ('owner', 'admin') then
    raise exception 'Only circle owners and admins can create channels'
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
    target_category_id,
    current_user_id
  )
  returning id into created_channel_id;

  return created_channel_id;
end;
$$;

-- Same as 202610130004_circle_nicknames, plus the circle's categories and
-- each channel's category_id.
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
          'nickname', cm.nickname,
          'is_current_user', cm.user_id = auth.uid(),
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
          'created_by', cc.created_by
        )
        order by cc.position, cc.created_at
      )
      from public.circle_channels cc
      where cc.circle_id = c.id
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

grant execute on function public.create_channel_category(uuid, text) to authenticated;
grant execute on function public.rename_channel_category(uuid, text) to authenticated;
grant execute on function public.delete_channel_category(uuid) to authenticated;
grant execute on function public.reorder_circle_channels(uuid, jsonb) to authenticated;
grant execute on function public.create_circle_channel(uuid, text, uuid) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
