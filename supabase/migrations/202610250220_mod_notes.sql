-- Moderator tools 2.0 (C5), part 3 of 9: moderator notes and warnings.
--
-- circle_mod_notes keeps what moderators write down about a member: a note
-- ("asked to stop posting links") or a warning (counted, on top of being a
-- note). Only people with moderate_members can add, read or count them, and
-- only about members ranked below them: the same rule as timing a member out.
-- The member never sees them. The audit log gets mod_note_add, mod_warn or
-- mod_note_delete without the text, so a note stays between moderators who
-- hold moderate_members and does not leak to everybody who reads the log.
--
-- The table is closed to clients; everything goes through the RPCs.

create table if not exists public.circle_mod_notes (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  author_id uuid references public.profiles(id) on delete set null,
  kind text not null default 'note' check (kind in ('note', 'warning')),
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists circle_mod_notes_member_idx
  on public.circle_mod_notes (circle_id, user_id, created_at desc);

create index if not exists circle_mod_notes_warning_idx
  on public.circle_mod_notes (circle_id, user_id)
  where kind = 'warning';

alter table public.circle_mod_notes enable row level security;
revoke all on public.circle_mod_notes from public, anon, authenticated;

-- Whether the caller may deal with [target_user_id] as a moderator: has
-- moderate_members, is not the target, and ranks above them. Raises the
-- right error otherwise.
create or replace function public.assert_can_moderate_member(
  target_circle_id uuid,
  target_user_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'moderate_members'
  ) then
    raise exception 'Only members who can time out members can do that'
      using errcode = '42501';
  end if;

  if target_user_id = current_user_id then
    raise exception 'You cannot do that to yourself' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.circle_members cm
    where cm.circle_id = target_circle_id
      and cm.user_id = target_user_id
  ) then
    raise exception 'Circle member not found' using errcode = 'P0002';
  end if;

  if public.circle_member_rank(target_circle_id, target_user_id)
    >= public.circle_member_rank(target_circle_id, current_user_id)
  then
    raise exception 'Cannot do that to a member ranked at or above you'
      using errcode = '42501';
  end if;
end;
$$;

revoke execute on function public.assert_can_moderate_member(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.add_circle_mod_note(
  target_circle_id uuid,
  target_user_id uuid,
  note_kind text,
  note_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  trimmed text := btrim(coalesce(note_body, ''));
  warning_count integer;
begin
  perform public.assert_can_moderate_member(target_circle_id, target_user_id);
  perform public.assert_circle_up(target_circle_id);

  if note_kind is null or note_kind not in ('note', 'warning') then
    raise exception 'Unknown note type' using errcode = '22023';
  end if;
  if char_length(trimmed) not between 1 and 1000 then
    raise exception 'A note is 1 to 1000 characters' using errcode = '22023';
  end if;

  insert into public.circle_mod_notes (circle_id, user_id, author_id, kind, body)
  values (target_circle_id, target_user_id, auth.uid(), note_kind, trimmed)
  returning id into new_id;

  select count(*) into warning_count
  from public.circle_mod_notes n
  where n.circle_id = target_circle_id
    and n.user_id = target_user_id
    and n.kind = 'warning';

  perform public.write_circle_audit(
    target_circle_id,
    case when note_kind = 'warning' then 'mod_warn' else 'mod_note_add' end,
    'member',
    target_user_id,
    public.circle_member_label(target_circle_id, target_user_id),
    case
      when note_kind = 'warning' then jsonb_build_object('warnings', warning_count)
      else '{}'::jsonb
    end
  );

  return new_id;
end;
$$;

-- The notes and warnings about a member, newest first:
-- {id, kind, body, author_id, author_name, created_at, can_delete}.
create or replace function public.list_circle_mod_notes(
  target_circle_id uuid,
  target_user_id uuid
)
returns table (
  id uuid,
  kind text,
  body text,
  author_id uuid,
  author_name text,
  created_at timestamptz,
  can_delete boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  can_manage boolean;
begin
  perform public.assert_can_moderate_member(target_circle_id, target_user_id);
  can_manage := public.current_user_has_circle_permission(
    target_circle_id, 'manage_circle');

  return query
  select
    n.id,
    n.kind,
    n.body,
    n.author_id,
    case
      when n.author_id is null then null
      else public.circle_member_label(target_circle_id, n.author_id)
    end,
    n.created_at,
    n.author_id = current_user_id or can_manage
  from public.circle_mod_notes n
  where n.circle_id = target_circle_id
    and n.user_id = target_user_id
  order by n.created_at desc
  limit 200;
end;
$$;

-- The author takes a note back, or someone who manages the circle does.
create or replace function public.delete_circle_mod_note(target_note_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  note_row public.circle_mod_notes%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select n.* into note_row
  from public.circle_mod_notes n
  where n.id = target_note_id
  for update;

  if note_row.id is null then
    raise exception 'Moderator note not found' using errcode = 'P0002';
  end if;

  if not public.current_user_has_circle_permission(
    note_row.circle_id, 'moderate_members')
    or not (
      note_row.author_id = current_user_id
      or public.current_user_has_circle_permission(note_row.circle_id, 'manage_circle')
    )
  then
    raise exception 'Only the author or a circle manager can delete a note'
      using errcode = '42501';
  end if;

  perform public.assert_circle_up(note_row.circle_id);

  delete from public.circle_mod_notes n where n.id = target_note_id;

  perform public.write_circle_audit(
    note_row.circle_id,
    'mod_note_delete',
    'member',
    note_row.user_id,
    public.circle_member_label(note_row.circle_id, note_row.user_id),
    jsonb_build_object('kind', note_row.kind)
  );
end;
$$;

revoke execute on function public.add_circle_mod_note(uuid, uuid, text, text)
  from public, anon;
revoke execute on function public.list_circle_mod_notes(uuid, uuid) from public, anon;
revoke execute on function public.delete_circle_mod_note(uuid) from public, anon;
grant execute on function public.add_circle_mod_note(uuid, uuid, text, text)
  to authenticated;
grant execute on function public.list_circle_mod_notes(uuid, uuid) to authenticated;
grant execute on function public.delete_circle_mod_note(uuid) to authenticated;
