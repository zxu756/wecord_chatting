-- L6 (scale): members of a big circle or group come a page at a time.
--
-- Before, opening a circle returned every member (get_circle_detail: 10000
-- profiles with a status, a bio check and the role ids of each, 0.7 s and a
-- 5 MB answer that the REST API would also cut at 1000 rows), and opening a
-- group read every member row with its profile. Now:
--
-- * get_circle_detail takes an optional member_limit. With it, the answer
--   holds the first member_limit members in the usual order (owner, admins,
--   then by name) and always the caller, and circle.member_count says how
--   many there are. Without it (the default) nothing changes.
-- * list_circle_members_page continues from where the list stopped, or
--   searches by name, a page at a time.
-- * list_conversation_members_page does the same for the members of a group
--   or channel conversation (the group sheet, and @ mentions: the candidates
--   for "@ma" come from a search of 8, not from a list of 5000).
--
-- Who may see whom is unchanged: a circle's members are for its members
-- (not while it is suspended), and a conversation's members are for its
-- members, without those who cannot see the channel (as the policy of
-- conversation_members says).

create or replace function pg_temp.l6_patch_text(fn regprocedure, pairs text[])
returns text
language plpgsql
as $$
declare
  def text := pg_get_functiondef(fn);
  patched text;
  i integer;
begin
  for i in 1..array_length(pairs, 1) by 2 loop
    patched := replace(def, pairs[i], pairs[i + 1]);
    if patched = def then
      raise exception 'L6 patch: expected text not found in %: %', fn, left(pairs[i], 80);
    end if;
    def := patched;
  end loop;
  return def;
end $$;

-- ---------------------------------------------------- get_circle_detail
do $do$
declare
  def text;
begin
  def := pg_temp.l6_patch_text('public.get_circle_detail(uuid)'::regprocedure, array[
$old$get_circle_detail(target_circle_id uuid)$old$,
$new$get_circle_detail(target_circle_id uuid, member_limit integer DEFAULT NULL::integer)$new$,
$old$      'current_user_permissions', caller.permissions
    ),
    'roles',$old$,
$new$      'current_user_permissions', caller.permissions,
      'member_count', (
        select count(*)
        from public.circle_members member_total
        where member_total.circle_id = c.id
      )
    ),
    'roles',$new$,
$old$      from public.circle_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.circle_id = c.id
    ), '[]'::jsonb),
    'channels',$old$,
$new$      from public.circle_members cm
      join public.profiles p on p.id = cm.user_id
      where cm.circle_id = c.id
        -- A page of a big circle (L6): the first member_limit in the order
        -- below, and the caller.
        and (
          member_limit is null
          or cm.user_id = auth.uid()
          or cm.user_id in (
            select first_members.user_id
            from (
              select m2.user_id
              from public.circle_members m2
              join public.profiles p2 on p2.id = m2.user_id
              where m2.circle_id = c.id
              order by
                case m2.role when 'owner' then 0 when 'admin' then 1 else 2 end,
                coalesce(m2.nickname, p2.display_name),
                m2.user_id
              limit greatest(member_limit, 1)
            ) first_members
          )
        )
    ), '[]'::jsonb),
    'channels',$new$
  ]);
  drop function public.get_circle_detail(uuid);
  execute def;
end $do$;

revoke execute on function public.get_circle_detail(uuid, integer) from public, anon;
grant execute on function public.get_circle_detail(uuid, integer) to authenticated;

-- ------------------------------------------------- list_circle_members_page
-- One member as get_circle_detail writes it (the app reads both the same
-- way), plus the keys the next page continues from.
create or replace function public.list_circle_members_page(
  target_circle_id uuid,
  page_size integer default 100,
  after_rank integer default null,
  after_name text default null,
  after_user_id uuid default null,
  search_text text default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'role', cm.role,
    'nickname', cm.nickname,
    'is_current_user', cm.user_id = auth.uid(),
    'timed_out_until', case
      when cm.timed_out_until > now() then cm.timed_out_until
    end,
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
      'bio', public.visible_profile_bio(p.id, p.bio),
      'created_at', p.created_at,
      'updated_at', p.updated_at,
      'custom_status', public.custom_status(p)
    ),
    'sort_rank', page.rank,
    'sort_name', page.sort_name
  )
  from (
    select
      cm2.user_id,
      case cm2.role when 'owner' then 0 when 'admin' then 1 else 2 end as rank,
      coalesce(cm2.nickname, p2.display_name) as sort_name
    from public.circle_members cm2
    join public.profiles p2 on p2.id = cm2.user_id
    where cm2.circle_id = target_circle_id
      -- Only members, and not while the circle is suspended.
      and exists (
        select 1
        from public.circle_members me
        join public.circles c on c.id = me.circle_id
        where me.circle_id = target_circle_id
          and me.user_id = auth.uid()
          and c.disabled_mode is distinct from 'suspend'
      )
      and (
        nullif(btrim(search_text), '') is null
        or position(lower(btrim(search_text)) in lower(coalesce(cm2.nickname, ''))) > 0
        or position(lower(btrim(search_text)) in lower(p2.display_name)) > 0
        or position(lower(btrim(search_text)) in lower(p2.username)) > 0
      )
      and (
        after_rank is null
        or (
          case cm2.role when 'owner' then 0 when 'admin' then 1 else 2 end,
          coalesce(cm2.nickname, p2.display_name),
          cm2.user_id
        ) > (after_rank, after_name, after_user_id)
      )
    order by
      case cm2.role when 'owner' then 0 when 'admin' then 1 else 2 end,
      coalesce(cm2.nickname, p2.display_name),
      cm2.user_id
    limit least(greatest(coalesce(page_size, 100), 1), 200)
  ) page
  join public.circle_members cm
    on cm.circle_id = target_circle_id
    and cm.user_id = page.user_id
  join public.profiles p on p.id = cm.user_id
  order by page.rank, page.sort_name, page.user_id;
$$;

revoke execute on function public.list_circle_members_page(uuid, integer, integer, text, uuid, text)
  from public, anon;
grant execute on function public.list_circle_members_page(uuid, integer, integer, text, uuid, text)
  to authenticated;

-- ------------------------------------------- list_conversation_members_page
-- The members of a group or channel conversation, oldest member first,
-- a page at a time, or those whose name or username contains search_text.
-- The same people the conversation_members policy shows the caller, with
-- the caller's own alias for each (what the group sheet read before).
create or replace function public.list_conversation_members_page(
  target_conversation_id uuid,
  page_size integer default 100,
  after_joined_at timestamptz default null,
  after_user_id uuid default null,
  search_text text default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  with access as (
    select
      public.is_current_user_conversation_member(target_conversation_id) as allowed,
      -- Only a circle's channels (and their threads) hide members who cannot
      -- see the channel; no per-member check anywhere else.
      exists (
        select 1
        from public.circle_channels cc
        where cc.conversation_id = coalesce(
          (
            select ct.parent_conversation_id
            from public.conversation_threads ct
            where ct.conversation_id = target_conversation_id
          ),
          target_conversation_id
        )
      ) as is_circle_channel
  )
  select jsonb_build_object(
    'role', cm.role,
    'circle_nickname', public.circle_nickname(cm),
    'joined_at', cm.joined_at,
    'profile', jsonb_build_object(
      'id', p.id,
      'username', p.username,
      'display_name', p.display_name,
      'avatar_url', p.avatar_url,
      'created_at', p.created_at,
      'updated_at', p.updated_at,
      'alias', ca.alias
    )
  )
  from public.conversation_members cm
  join public.profiles p on p.id = cm.user_id
  left join public.contact_aliases ca
    on ca.owner_id = auth.uid()
    and ca.friend_id = p.id
  cross join access
  where cm.conversation_id = target_conversation_id
    and (
      after_joined_at is null
      or (cm.joined_at, cm.user_id) > (after_joined_at, after_user_id)
    )
    and (
      nullif(btrim(search_text), '') is null
      or position(lower(btrim(search_text)) in lower(p.display_name)) > 0
      or position(lower(btrim(search_text)) in lower(p.username)) > 0
      or position(lower(btrim(search_text)) in lower(coalesce(ca.alias, ''))) > 0
      or position(lower(btrim(search_text)) in lower(coalesce(public.circle_nickname(cm), ''))) > 0
    )
    -- As the conversation_members policy: your own row always, the others'
    -- when you may read the conversation and they may see the channel.
    and (
      cm.user_id = auth.uid()
      or (
        access.allowed
        and (
          not access.is_circle_channel
          or public.user_has_conversation_channel_permission(
            target_conversation_id,
            cm.user_id,
            'view_channel'
          )
        )
      )
    )
  order by cm.joined_at, cm.user_id
  limit least(greatest(coalesce(page_size, 100), 1), 500);
$$;

revoke execute on function public.list_conversation_members_page(uuid, integer, timestamptz, uuid, text)
  from public, anon;
grant execute on function public.list_conversation_members_page(uuid, integer, timestamptz, uuid, text)
  to authenticated;

-- A page of members is read in joining order: the index makes it a range
-- scan instead of sorting the whole group.
create index if not exists conversation_members_page_idx
  on public.conversation_members (conversation_id, joined_at, user_id);
