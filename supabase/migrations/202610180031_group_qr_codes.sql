-- Group QR code: https://wecord.jokebear.fyi/g/<code>.
--
-- A group chat (not a circle: circles have invite links, see
-- 202610130003_circle_invites) can show a QR code that lets people join.
--
-- * One code per group. It works for 7 days (like WeChat) and "Refresh"
--   replaces it with a new one, which invalidates the old one at once. A
--   code that ran out is made again the next time someone who may asks.
-- * Who may make it: whoever may add members, which for groups is the owner
--   and the admins (add_group_members, 202605180005_social_chat_v2). The
--   same rule keeps a code working: when the person who made it is no
--   longer an owner or admin of the group (demoted, removed or left) the
--   code stops working, so it never outlives the right to add people.
-- * Who may join: any signed-in user with the code, unless the person who
--   made it blocked them or they blocked that person. Friends are not
--   required (that is the point of a QR code). People already in the group
--   just open it.
-- * The table takes no direct reads or writes; get_group_qr,
--   preview_group_qr and join_group_by_qr are the only ways in.

create table if not exists public.group_qr_codes (
  conversation_id uuid primary key
    references public.conversations(id) on delete cascade,
  code text not null unique,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.group_qr_codes enable row level security;
revoke all on public.group_qr_codes from anon, authenticated;

create or replace function public.generate_group_qr_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'abcdefghijkmnpqrstuvwxyz23456789';
  random_bytes bytea := extensions.gen_random_bytes(16);
  generated_code text := '';
begin
  for byte_index in 0..15 loop
    generated_code := generated_code
      || substr(alphabet, (get_byte(random_bytes, byte_index) % 32) + 1, 1);
  end loop;
  return generated_code;
end;
$$;

revoke execute on function public.generate_group_qr_code() from public, anon, authenticated;

-- The group's code and when it expires, made (or made again when it ran
-- out, or when refresh is true) for owners and admins of the group.
-- Returns {code, created_at, expires_at}.
create or replace function public.get_group_qr(
  target_conversation_id uuid,
  refresh boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  current_row public.group_qr_codes%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.conversations c
    join public.conversation_members cm on cm.conversation_id = c.id
    where c.id = target_conversation_id
      and c.type = 'group'
      and cm.user_id = current_user_id
      and cm.role in ('owner', 'admin')
  ) then
    raise exception 'Only an owner or an admin can share the group QR code'
      using errcode = '42501';
  end if;

  -- Two admins asking at once get the same code.
  perform pg_advisory_xact_lock(
    hashtextextended('group-qr:' || target_conversation_id::text, 0)
  );

  select * into current_row
  from public.group_qr_codes q
  where q.conversation_id = target_conversation_id;

  if current_row.conversation_id is null
    or coalesce(refresh, false)
    or current_row.expires_at <= now()
    -- A code made by someone who may no longer add members is replaced.
    or current_row.created_by is distinct from current_user_id
      and not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = target_conversation_id
          and cm.user_id = current_row.created_by
          and cm.role in ('owner', 'admin')
      )
  then
    loop
      begin
        insert into public.group_qr_codes as q (
          conversation_id, code, created_by, created_at, expires_at
        )
        values (
          target_conversation_id,
          public.generate_group_qr_code(),
          current_user_id,
          now(),
          now() + interval '7 days'
        )
        on conflict (conversation_id) do update
        set code = excluded.code,
          created_by = excluded.created_by,
          created_at = excluded.created_at,
          expires_at = excluded.expires_at
        returning * into current_row;
        exit;
      exception when unique_violation then
        null;
      end;
    end loop;
  end if;

  return jsonb_build_object(
    'code', current_row.code,
    'created_at', current_row.created_at,
    'expires_at', current_row.expires_at
  );
end;
$$;

-- Whether a code can be used right now: the group's row and the reason when
-- not. Shared by preview_group_qr and join_group_by_qr.
create or replace function public.group_qr_state(qr_code text)
returns table (
  conversation_id uuid,
  created_by uuid,
  expires_at timestamptz,
  state text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    q.conversation_id,
    q.created_by,
    q.expires_at,
    case
      when c.id is null or c.type <> 'group' then 'not_found'
      when public.are_users_blocked(auth.uid(), q.created_by) then 'not_found'
      when q.expires_at <= now() then 'expired'
      when not exists (
        select 1
        from public.conversation_members cm
        where cm.conversation_id = q.conversation_id
          and cm.user_id = q.created_by
          and cm.role in ('owner', 'admin')
      ) then 'expired'
      else 'ok'
    end
  from public.group_qr_codes q
  left join public.conversations c on c.id = q.conversation_id
  where auth.uid() is not null
    and q.code = lower(btrim(coalesce(qr_code, '')));
$$;

revoke execute on function public.group_qr_state(text) from public, anon, authenticated;

-- What the join page shows: {state, conversation_id, title, avatar_url,
-- member_count, expires_at, is_member}. state is 'ok', 'expired' or
-- 'not_found' (unknown code, or the person who made it blocked the caller);
-- nothing about the group is returned unless it is 'ok' (or the caller is
-- already in the group).
create or replace function public.preview_group_qr(qr_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  qr record;
  group_row public.conversations%rowtype;
  already_member boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select * into qr from public.group_qr_state(qr_code);
  if qr.conversation_id is null then
    return jsonb_build_object('state', 'not_found');
  end if;

  select exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = qr.conversation_id
      and cm.user_id = current_user_id
  ) into already_member;

  if qr.state <> 'ok' and not already_member then
    return jsonb_build_object('state', qr.state);
  end if;

  select * into group_row
  from public.conversations c
  where c.id = qr.conversation_id;

  return jsonb_build_object(
    'state', qr.state,
    'conversation_id', qr.conversation_id,
    'title', group_row.title,
    'avatar_url', group_row.avatar_url,
    'member_count', (
      select count(*) from public.conversation_members cm
      where cm.conversation_id = qr.conversation_id
    ),
    'expires_at', qr.expires_at,
    'is_member', already_member
  );
end;
$$;

-- Joins the group a code leads to. Returns {state, conversation_id}: state is
-- 'joined', 'already_member', 'expired' or 'not_found'.
create or replace function public.join_group_by_qr(qr_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  qr record;
  joiner_deleted boolean;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select p.deleted_at is not null into joiner_deleted
  from public.profiles p
  where p.id = current_user_id;
  if joiner_deleted is distinct from false then
    raise exception 'This account cannot join groups' using errcode = '42501';
  end if;

  select * into qr from public.group_qr_state(qr_code);
  if qr.conversation_id is null then
    return jsonb_build_object('state', 'not_found');
  end if;

  if exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = qr.conversation_id
      and cm.user_id = current_user_id
  ) then
    return jsonb_build_object(
      'state', 'already_member',
      'conversation_id', qr.conversation_id
    );
  end if;

  if qr.state <> 'ok' then
    return jsonb_build_object('state', qr.state);
  end if;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (qr.conversation_id, current_user_id, 'member')
  on conflict (conversation_id, user_id) do nothing;

  return jsonb_build_object(
    'state', 'joined',
    'conversation_id', qr.conversation_id
  );
end;
$$;

revoke execute on function public.get_group_qr(uuid, boolean) from public, anon;
revoke execute on function public.preview_group_qr(text) from public, anon;
revoke execute on function public.join_group_by_qr(text) from public, anon;
grant execute on function public.get_group_qr(uuid, boolean) to authenticated;
grant execute on function public.preview_group_qr(text) to authenticated;
grant execute on function public.join_group_by_qr(text) to authenticated;
