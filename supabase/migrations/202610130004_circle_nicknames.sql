-- Per-circle nicknames. A member's nickname replaces their display name
-- inside that circle: the member list, channel messages and @mention
-- candidates. Stored trimmed, 1 to 32 characters; null means no nickname.
alter table public.circle_members
  add column if not exists nickname text;

alter table public.circle_members
  drop constraint if exists circle_members_nickname_length;
alter table public.circle_members
  add constraint circle_members_nickname_length check (
    nickname is null
    or (nickname = btrim(nickname) and char_length(nickname) between 1 and 32)
  );

-- The circle nickname of a user in a circle channel conversation, or null
-- for other conversations. Only the circle's own members can see it.
create or replace function public.circle_channel_nickname(
  target_conversation_id uuid,
  target_user_id uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select cm.nickname
  from public.circle_channels cc
  join public.circle_members cm
    on cm.circle_id = cc.circle_id
    and cm.user_id = target_user_id
  where cc.conversation_id = target_conversation_id
    and public.is_current_user_circle_member(cc.circle_id);
$$;

revoke execute on function public.circle_channel_nickname(uuid, uuid) from public;
revoke execute on function public.circle_channel_nickname(uuid, uuid) from anon;
revoke execute on function public.circle_channel_nickname(uuid, uuid) from authenticated;

-- PostgREST computed field: `messages?select=*,sender_nickname`.
create or replace function public.sender_nickname(message_row public.messages)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_nickname(
    message_row.conversation_id,
    message_row.sender_id
  );
$$;

-- PostgREST computed field: `conversation_members?select=*,circle_nickname`.
create or replace function public.circle_nickname(
  member_row public.conversation_members
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_channel_nickname(
    member_row.conversation_id,
    member_row.user_id
  );
$$;

-- Members may always set their own nickname. Owners and admins may set
-- anyone's, except that only the owner may change the owner's. A null or
-- blank nickname clears it. Returns the stored nickname.
create or replace function public.set_circle_nickname(
  target_circle_id uuid,
  target_user_id uuid,
  nickname text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_nickname text := nullif(btrim(coalesce(nickname, '')), '');
  caller_role text;
  target_role text;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if normalized_nickname is not null
    and char_length(normalized_nickname) > 32
  then
    raise exception 'Nickname must be 1 to 32 characters'
      using errcode = '22023';
  end if;

  select public.current_user_circle_role(target_circle_id) into caller_role;

  if caller_role is null then
    raise exception 'Only circle members can set nicknames'
      using errcode = '42501';
  end if;

  select cm.role
  into target_role
  from public.circle_members cm
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id
  for update;

  if target_role is null then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if target_user_id <> current_user_id then
    if caller_role not in ('owner', 'admin') then
      raise exception 'Only circle owners and admins can change other nicknames'
        using errcode = '42501';
    end if;

    if target_role = 'owner' and caller_role <> 'owner' then
      raise exception 'Only the circle owner can change the owner nickname'
        using errcode = '42501';
    end if;
  end if;

  update public.circle_members cm
  set nickname = normalized_nickname
  where cm.circle_id = target_circle_id
    and cm.user_id = target_user_id;

  return normalized_nickname;
end;
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

grant execute on function public.sender_nickname(public.messages) to authenticated;
grant execute on function public.circle_nickname(public.conversation_members) to authenticated;
grant execute on function public.set_circle_nickname(uuid, uuid, text) to authenticated;
grant execute on function public.get_circle_detail(uuid) to authenticated;
