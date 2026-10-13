-- Custom emoji and stickers, like Discord's: each circle uploads up to 50
-- emoji and 20 stickers (PNG, GIF or WebP, at most 256 KB).
--
-- * circle_emojis: one row per emoji or sticker; names are 2 to 32 of
--   a-z, 0-9 and _, unique per circle and kind. Members of the circle read
--   them; only the RPCs below write them.
-- * Storage: the private bucket circle-emojis holds the images at
--   <circle_id>/<uuid>.<png|gif|webp>. Members of the circle read them
--   (signed URLs); members with manage_emojis upload and delete them. The
--   bucket itself limits size and type.
-- * create_circle_emoji (after the client uploaded the image; the object
--   must exist in the circle's folder), rename_circle_emoji and
--   delete_circle_emoji need manage_emojis and are audited as
--   emoji_create/update/delete or sticker_create/update/delete.
--   delete_circle_emoji returns the image's path for the client to remove
--   from Storage, and drops reactions with the emoji.
-- * list_circle_emojis(circle_id) for members; list_my_usable_emojis()
--   lists the emoji and stickers of every circle the caller is in. They
--   are usable anywhere, but render as images only for members of their
--   circle (others see :name:).
-- * Messages write emoji as <:name:uuid>. Reactions use custom:<uuid>:
--   toggle_message_reaction only adds one for an emoji of a circle the
--   caller is in; reactions() also returns its name as custom_name.
-- * Stickers are messages of type 'sticker' sent by send_sticker (the
--   sender must be in the sticker's circle; the send trigger applies as
--   usual): body is the sticker's name (previews, notifications and search
--   see it) and attachment {kind: 'sticker', emoji_id, name, circle_id}.
--   Clients cannot insert stickers directly, edit them or forward them.

create table if not exists public.circle_emojis (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  name text not null,
  kind text not null,
  storage_path text not null unique,
  mime_type text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint circle_emojis_name_format check (name ~ '^[a-z0-9_]{2,32}$'),
  constraint circle_emojis_kind_check check (kind in ('emoji', 'sticker')),
  constraint circle_emojis_mime_type_check
    check (mime_type in ('image/png', 'image/gif', 'image/webp')),
  constraint circle_emojis_name_unique unique (circle_id, kind, name)
);

alter table public.circle_emojis enable row level security;

revoke insert, update, delete, truncate on public.circle_emojis from anon;
revoke insert, update, delete, truncate on public.circle_emojis from authenticated;

drop policy if exists circle_emojis_select_member on public.circle_emojis;
create policy circle_emojis_select_member
  on public.circle_emojis for select
  to authenticated
  using (public.is_current_user_circle_member(circle_id));

-- The circle an object of the circle-emojis bucket belongs to: its first
-- folder, or null when that is not a uuid.
create or replace function public.circle_emoji_object_circle_id(
  object_name text
)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
begin
  if object_name is null
    or object_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
  then
    return null;
  end if;
  return split_part(object_name, '/', 1)::uuid;
end;
$$;

revoke execute on function public.circle_emoji_object_circle_id(text) from public;
revoke execute on function public.circle_emoji_object_circle_id(text) from anon;
grant execute on function public.circle_emoji_object_circle_id(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'circle-emojis',
  'circle-emojis',
  false,
  262144,
  array['image/png', 'image/gif', 'image/webp']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists circle_emojis_storage_select_member on storage.objects;
create policy circle_emojis_storage_select_member
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'circle-emojis'
    and public.is_current_user_circle_member(
      public.circle_emoji_object_circle_id(name)
    )
  );

drop policy if exists circle_emojis_storage_insert_manager on storage.objects;
create policy circle_emojis_storage_insert_manager
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'circle-emojis'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|gif|webp)$'
    and public.current_user_has_circle_permission(
      public.circle_emoji_object_circle_id(name),
      'manage_emojis'
    )
  );

drop policy if exists circle_emojis_storage_delete_manager on storage.objects;
create policy circle_emojis_storage_delete_manager
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'circle-emojis'
    and public.current_user_has_circle_permission(
      public.circle_emoji_object_circle_id(name),
      'manage_emojis'
    )
  );

-- An emoji or sticker as clients see it.
create or replace function public.circle_emoji_payload(
  emoji public.circle_emojis
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', emoji.id,
    'circle_id', emoji.circle_id,
    'circle_name', (select c.name from public.circles c where c.id = emoji.circle_id),
    'name', emoji.name,
    'kind', emoji.kind,
    'storage_path', emoji.storage_path,
    'mime_type', emoji.mime_type,
    'created_by', emoji.created_by,
    'creator_name', case
      when emoji.created_by is null then null
      else public.circle_member_label(emoji.circle_id, emoji.created_by)
    end,
    'created_at', emoji.created_at
  );
$$;

-- The emoji, when the caller may manage it (manage_emojis in its circle);
-- raises otherwise.
create or replace function public.circle_emoji_for_management(
  target_emoji_id uuid
)
returns public.circle_emojis
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  emoji public.circle_emojis%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.*
  into emoji
  from public.circle_emojis e
  where e.id = target_emoji_id;

  if emoji.id is null
    or not public.current_user_has_circle_permission(
      emoji.circle_id,
      'manage_emojis'
    )
  then
    raise exception 'Emoji not found or caller cannot manage it'
      using errcode = '42501';
  end if;

  return emoji;
end;
$$;

revoke execute on function public.circle_emoji_payload(public.circle_emojis) from public;
revoke execute on function public.circle_emoji_payload(public.circle_emojis) from anon;
revoke execute on function public.circle_emoji_payload(public.circle_emojis) from authenticated;
revoke execute on function public.circle_emoji_for_management(uuid) from public;
revoke execute on function public.circle_emoji_for_management(uuid) from anon;
revoke execute on function public.circle_emoji_for_management(uuid) from authenticated;

-- Registers an image the caller uploaded to <circle_id>/<uuid>.<ext> as an
-- emoji or sticker. Raises 22023 for invalid input, 23505 when the name is
-- taken, 54000 when the circle has no room left.
create or replace function public.create_circle_emoji(
  target_circle_id uuid,
  emoji_name text,
  emoji_kind text,
  storage_path text,
  mime_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  trimmed_name text := btrim(coalesce(emoji_name, ''));
  object_path text := coalesce(storage_path, '');
  stored_object storage.objects%rowtype;
  existing_count integer;
  violated_constraint text;
  created public.circle_emojis%rowtype;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.current_user_has_circle_permission(
    target_circle_id,
    'manage_emojis'
  ) then
    raise exception 'Circle not found or caller cannot manage its emoji'
      using errcode = '42501';
  end if;

  if trimmed_name !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'Names are 2 to 32 lowercase letters, digits or underscores'
      using errcode = '22023';
  end if;

  if emoji_kind is null or emoji_kind not in ('emoji', 'sticker') then
    raise exception 'Kind must be emoji or sticker' using errcode = '22023';
  end if;

  if mime_type is null
    or mime_type not in ('image/png', 'image/gif', 'image/webp')
  then
    raise exception 'Images must be PNG, GIF or WebP' using errcode = '22023';
  end if;

  if public.circle_emoji_object_circle_id(object_path) is distinct from target_circle_id
    or object_path !~ '^[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|gif|webp)$'
  then
    raise exception 'The image must be uploaded to the circle''s folder'
      using errcode = '22023';
  end if;

  select o.*
  into stored_object
  from storage.objects o
  where o.bucket_id = 'circle-emojis'
    and o.name = object_path;

  if stored_object.id is null then
    raise exception 'The image was not uploaded' using errcode = '22023';
  end if;

  if coalesce((stored_object.metadata->>'size')::bigint, 0) > 262144
    or coalesce(stored_object.metadata->>'mimetype', mime_type) <> mime_type
  then
    raise exception 'Images must be PNG, GIF or WebP of at most 256 KB'
      using errcode = '22023';
  end if;

  -- One upload per circle at a time, so the limits hold.
  perform 1
  from public.circles c
  where c.id = target_circle_id
  for update;

  select count(*)
  into existing_count
  from public.circle_emojis e
  where e.circle_id = target_circle_id
    and e.kind = emoji_kind;

  -- At most 50 emoji and 20 stickers per circle.
  if existing_count >= (case when emoji_kind = 'emoji' then 50 else 20 end) then
    raise exception 'This circle has no room for more %', emoji_kind || 's'
      using errcode = '54000';
  end if;

  begin
    insert into public.circle_emojis (
      circle_id,
      name,
      kind,
      storage_path,
      mime_type,
      created_by
    )
    values (
      target_circle_id,
      trimmed_name,
      emoji_kind,
      object_path,
      mime_type,
      current_user_id
    )
    returning * into created;
  exception
    when unique_violation then
      get stacked diagnostics violated_constraint = constraint_name;
      if violated_constraint = 'circle_emojis_name_unique' then
        raise exception 'That name is already taken' using errcode = '23505';
      end if;
      raise exception 'That image is already in use' using errcode = '22023';
  end;

  perform public.write_circle_audit(
    target_circle_id,
    emoji_kind || '_create',
    emoji_kind,
    created.id,
    created.name,
    '{}'::jsonb
  );

  return public.circle_emoji_payload(created);
end;
$$;

create or replace function public.rename_circle_emoji(
  target_emoji_id uuid,
  emoji_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  emoji public.circle_emojis%rowtype :=
    public.circle_emoji_for_management(target_emoji_id);
  trimmed_name text := btrim(coalesce(emoji_name, ''));
  renamed public.circle_emojis%rowtype;
begin
  if trimmed_name !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'Names are 2 to 32 lowercase letters, digits or underscores'
      using errcode = '22023';
  end if;

  if trimmed_name = emoji.name then
    return public.circle_emoji_payload(emoji);
  end if;

  begin
    update public.circle_emojis e
    set name = trimmed_name
    where e.id = emoji.id
    returning * into renamed;
  exception
    when unique_violation then
      raise exception 'That name is already taken' using errcode = '23505';
  end;

  perform public.write_circle_audit(
    emoji.circle_id,
    emoji.kind || '_update',
    emoji.kind,
    emoji.id,
    renamed.name,
    jsonb_build_object(
      'name',
      jsonb_build_object('old', emoji.name, 'new', renamed.name)
    )
  );

  return public.circle_emoji_payload(renamed);
end;
$$;

-- Deletes an emoji or sticker and the reactions with it. Returns the
-- image's path, which the client removes from Storage. Sent stickers stay
-- as messages but no longer show the image.
create or replace function public.delete_circle_emoji(target_emoji_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  emoji public.circle_emojis%rowtype :=
    public.circle_emoji_for_management(target_emoji_id);
begin
  delete from public.circle_emojis e
  where e.id = emoji.id;

  if emoji.kind = 'emoji' then
    delete from public.message_reactions mr
    where mr.emoji = 'custom:' || emoji.id::text;
  end if;

  perform public.write_circle_audit(
    emoji.circle_id,
    emoji.kind || '_delete',
    emoji.kind,
    emoji.id,
    emoji.name,
    '{}'::jsonb
  );

  return emoji.storage_path;
end;
$$;

create or replace function public.list_circle_emojis(target_circle_id uuid)
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

  if not public.is_current_user_circle_member(target_circle_id) then
    raise exception 'Circle not found or caller is not a member'
      using errcode = '42501';
  end if;

  return query
  select public.circle_emoji_payload(e)
  from public.circle_emojis e
  where e.circle_id = target_circle_id
  order by e.kind, e.name, e.id;
end;
$$;

-- The emoji and stickers of every circle the caller is in.
create or replace function public.list_my_usable_emojis()
returns setof jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.circle_emoji_payload(e)
  from public.circle_emojis e
  join public.circle_members cm
    on cm.circle_id = e.circle_id
    and cm.user_id = auth.uid()
  order by e.circle_id, e.kind, e.name, e.id;
$$;

-- Messages: the 'sticker' type, inserted only by send_sticker.
alter table public.messages
  drop constraint if exists messages_type_check;

alter table public.messages
  add constraint messages_type_check
  check (type in ('text', 'image', 'file', 'voice', 'system', 'poll', 'sticker'));

-- Same as 202610130025_moderator_message_delete, but stickers are sent
-- only by send_sticker.
drop policy if exists messages_insert_member on public.messages;

create policy messages_insert_member
  on public.messages for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type <> 'system'
    and type <> 'poll'
    and type <> 'sticker'
    and forwarded_from is null
    and webhook_id is null
    and webhook_name is null
    and webhook_avatar_url is null
    and recalled_by is null
    and public.is_current_user_conversation_member(conversation_id)
    and not public.is_current_user_blocked_in_conversation(conversation_id)
  );

create or replace function public.send_sticker(
  target_conversation_id uuid,
  target_emoji_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  sticker public.circle_emojis%rowtype;
  created_message_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select e.*
  into sticker
  from public.circle_emojis e
  where e.id = target_emoji_id
    and e.kind = 'sticker';

  if sticker.id is null
    or not public.is_current_user_circle_member(sticker.circle_id)
  then
    raise exception 'Sticker not found or caller cannot use it'
      using errcode = '42501';
  end if;

  if not public.is_current_user_conversation_member(target_conversation_id) then
    raise exception 'Conversation not found or caller is not a member'
      using errcode = '42501';
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Cannot send messages in this conversation'
      using errcode = '42501';
  end if;

  -- The send trigger checks send_messages and slowmode in circle channels.
  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment
  )
  values (
    target_conversation_id,
    current_user_id,
    'sticker',
    sticker.name,
    jsonb_build_object(
      'kind', 'sticker',
      'emoji_id', sticker.id,
      'name', sticker.name,
      'circle_id', sticker.circle_id
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

-- Same as 202610130023_polls, but stickers cannot be forwarded either: the
-- recipients may not be in the sticker's circle.
create or replace function public.forward_message(
  source_message_id uuid,
  target_conversation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_message public.messages%rowtype;
  source_sender_name text;
  created_message_id uuid;
begin
  select *
  into source_message
  from public.messages
  where id = source_message_id
    and recalled_at is null
    and type <> 'system'
    and type <> 'poll'
    and type <> 'sticker';

  if source_message.id is null
    or not public.is_current_user_conversation_member(source_message.conversation_id)
    or not public.is_current_user_conversation_member(target_conversation_id)
    or public.is_current_user_blocked_in_conversation(target_conversation_id)
  then
    raise exception 'Message cannot be forwarded' using errcode = '42501';
  end if;

  select display_name
  into source_sender_name
  from public.profiles
  where id = source_message.sender_id;

  insert into public.messages (
    conversation_id,
    sender_id,
    type,
    body,
    attachment,
    forwarded_from
  )
  values (
    target_conversation_id,
    auth.uid(),
    source_message.type,
    source_message.body,
    source_message.attachment,
    jsonb_build_object(
      'message_id', source_message.id,
      'sender_id', source_message.sender_id,
      'sender_name', source_sender_name,
      'type', source_message.type,
      'body', source_message.body,
      'source_attachment_bucket', source_message.attachment->>'bucket',
      'source_attachment_path', source_message.attachment->>'path'
    )
  )
  returning id into created_message_id;

  return created_message_id;
end;
$$;

-- Same as 202610130001_message_reactions, but a custom:<uuid> reaction is
-- only added for an emoji of a circle the caller is in (removing one is
-- always allowed).
create or replace function public.toggle_message_reaction(
  target_message_id uuid,
  target_emoji text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_emoji text := btrim(coalesce(target_emoji, ''));
  target_conversation_id uuid;
begin
  if current_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if char_length(normalized_emoji) not between 1 and 64 then
    raise exception 'Reaction emoji must be 1 to 64 characters'
      using errcode = '22023';
  end if;

  select m.conversation_id
  into target_conversation_id
  from public.messages m
  where m.id = target_message_id
    and m.recalled_at is null;

  if target_conversation_id is null
    or not public.is_current_user_conversation_member(target_conversation_id)
  then
    raise exception 'Message not found or caller is not a member'
      using errcode = '42501';
  end if;

  delete from public.message_reactions
  where message_id = target_message_id
    and user_id = current_user_id
    and emoji = normalized_emoji;

  if found then
    return false;
  end if;

  if public.is_current_user_blocked_in_conversation(target_conversation_id) then
    raise exception 'Message cannot be reacted to' using errcode = '42501';
  end if;

  if normalized_emoji like 'custom:%'
    and (
      normalized_emoji !~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or not exists (
        select 1
        from public.circle_emojis e
        join public.circle_members cm
          on cm.circle_id = e.circle_id
          and cm.user_id = current_user_id
        where e.id = substr(normalized_emoji, 8)::uuid
          and e.kind = 'emoji'
      )
    )
  then
    raise exception 'Unknown custom emoji' using errcode = '22023';
  end if;

  insert into public.message_reactions (
    message_id,
    user_id,
    emoji,
    conversation_id
  )
  values (
    target_message_id,
    current_user_id,
    normalized_emoji,
    target_conversation_id
  )
  on conflict do nothing;

  return true;
end;
$$;

-- Same as 202610130001_message_reactions, plus the name of custom emoji
-- (custom_name), so clients outside the emoji's circle show :name:.
create or replace function public.reactions(message_row public.messages)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'emoji', grouped.emoji,
        'count', grouped.reaction_count,
        'reacted_by_me', grouped.reacted_by_me,
        'custom_name', custom_emoji.name
      ))
      order by grouped.first_reacted_at, grouped.emoji
    ),
    '[]'::jsonb
  )
  from (
    select
      mr.emoji,
      count(*)::integer as reaction_count,
      coalesce(bool_or(mr.user_id = auth.uid()), false) as reacted_by_me,
      min(mr.created_at) as first_reacted_at
    from public.message_reactions mr
    join public.messages m on m.id = mr.message_id
    where mr.message_id = message_row.id
      and m.recalled_at is null
      and public.is_current_user_conversation_member(mr.conversation_id)
    group by mr.emoji
  ) grouped
  left join public.circle_emojis custom_emoji
    on custom_emoji.id = case
      when grouped.emoji ~ '^custom:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then substr(grouped.emoji, 8)::uuid
    end;
$$;

grant execute on function public.create_circle_emoji(uuid, text, text, text, text) to authenticated;
grant execute on function public.rename_circle_emoji(uuid, text) to authenticated;
grant execute on function public.delete_circle_emoji(uuid) to authenticated;
grant execute on function public.list_circle_emojis(uuid) to authenticated;
grant execute on function public.list_my_usable_emojis() to authenticated;
grant execute on function public.send_sticker(uuid, uuid) to authenticated;
grant execute on function public.forward_message(uuid, uuid) to authenticated;
grant execute on function public.toggle_message_reaction(uuid, text) to authenticated;
grant execute on function public.reactions(public.messages) to authenticated;
