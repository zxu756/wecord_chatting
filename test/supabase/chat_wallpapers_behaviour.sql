-- Behaviour checks for chat wallpapers (migration 202610170110). Run by
-- test/supabase/chat_wallpapers_test.dart against the local database inside
-- a transaction that is rolled back, so the database is left as it was. Run
-- from the repository root.
\set ON_ERROR_STOP on

begin;

-- Behaviour scripts that apply DDL take turns.
select pg_advisory_xact_lock(20261017);

\i supabase/migrations/202610170110_chat_wallpapers.sql

create temp table ids (name text primary key, id uuid not null);
grant all on ids to public;

insert into auth.users (id, email, instance_id, aud, role)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada@wall.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob@wall.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy@wall.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
insert into public.profiles (id, username, display_name)
values
  ('00000000-0000-4000-8000-0000000000a1', 'ada_wall', 'Ada'),
  ('00000000-0000-4000-8000-0000000000b1', 'bob_wall', 'Bob'),
  ('00000000-0000-4000-8000-0000000000c1', 'cy_wall', 'Cy');

-- Ada and Bob chat directly; Cy is not in it. Ada and Cy have another chat.
with dm as (
  insert into public.conversations (type) values ('direct') returning id
), dm_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select dm.id, member.id
  from dm, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid),
    ('00000000-0000-4000-8000-0000000000b1'::uuid)
  ) as member(id)
), other as (
  insert into public.conversations (type) values ('direct') returning id
), other_members as (
  insert into public.conversation_members (conversation_id, user_id)
  select other.id, member.id
  from other, (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid),
    ('00000000-0000-4000-8000-0000000000c1'::uuid)
  ) as member(id)
)
insert into ids select 'dm', id from dm union all select 'other', id from other;

create function pg_temp.as_user(user_id uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end $$;

-- The bucket: private, image only, size limited.
do $$
declare
  failures text := '';
begin
  if not exists (
    select 1 from storage.buckets
    where id = 'wallpapers'
      and not public
      and file_size_limit between 1 and 5242880
      and allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
  ) then
    failures := failures || E'\nthe wallpapers bucket is not private, small and image only';
  end if;
  if failures <> '' then
    raise exception 'bucket checks failed:%', failures;
  end if;
end $$;

-- Rows: set, replace, clear; shape rules; only your own.
do $$
declare
  dm uuid := (select id from ids where name = 'dm');
  other uuid := (select id from ids where name = 'other');
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  ada_photo text := '00000000-0000-4000-8000-0000000000a1/11111111-1111-4111-8111-111111111111.jpg';
  ada_photo2 text := '00000000-0000-4000-8000-0000000000a1/22222222-2222-4222-8222-222222222222.jpg';
  bob_photo text := '00000000-0000-4000-8000-0000000000b1/33333333-3333-4333-8333-333333333333.jpg';
  freed text;
  seen integer;
  failed boolean;
  failures text := '';
begin
  -- Ada sets her default and a wallpaper for the chat with Bob.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  perform public.set_chat_wallpaper(null, 'preset', 'dawn');
  perform public.set_chat_wallpaper(dm, 'photo', null, ada_photo, 0.5, true, 0.25, -0.5);
  select count(*) into seen from public.chat_wallpapers;
  execute 'reset role';
  if seen <> 2 then
    failures := failures || format(E'\nAda sees %s of her 2 rows', seen);
  end if;

  -- Setting again replaces in place and frees the old photo.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  select public.set_chat_wallpaper(dm, 'photo', null, ada_photo2, 0.3, false, 0, 0) into freed;
  execute 'reset role';
  if freed is distinct from ada_photo then
    failures := failures || format(E'\nreplacing freed %s', freed);
  end if;
  if (select count(*) from public.chat_wallpapers where user_id = ada) <> 2 then
    failures := failures || E'\nreplacing added a row';
  end if;
  if not exists (
    select 1 from public.chat_wallpapers
    where user_id = ada and conversation_id = dm and photo_path = ada_photo2
      and dim = 0.3::real and not blur
  ) then
    failures := failures || E'\nthe replacement was not stored';
  end if;

  -- Changing the default to a preset keeps a single default row.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  perform public.set_chat_wallpaper(null, 'preset', 'sand');
  execute 'reset role';
  if (select count(*) from public.chat_wallpapers where user_id = ada and conversation_id is null) <> 1
     or (select preset_id from public.chat_wallpapers where user_id = ada and conversation_id is null) <> 'sand' then
    failures := failures || E'\nthe default was not replaced in place';
  end if;

  -- Bob sees none of Ada's rows and has his own.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  perform public.set_chat_wallpaper(dm, 'preset', 'dots');
  select count(*) into seen from public.chat_wallpapers where user_id = ada;
  execute 'reset role';
  if seen <> 0 then
    failures := failures || E'\nBob can read Ada''s wallpapers';
  end if;
  if (select preset_id from public.chat_wallpapers where user_id = ada and conversation_id = dm) is not null then
    failures := failures || E'\nBob changed what Ada sees';
  end if;
  if (select preset_id from public.chat_wallpapers where user_id = bob and conversation_id = dm) <> 'dots' then
    failures := failures || E'\nBob''s own wallpaper was not stored';
  end if;

  -- Writing as someone else is refused by row level security.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  failed := false;
  begin
    insert into public.chat_wallpapers (user_id, kind, preset_id)
    values (ada, 'preset', 'grid');
  exception when insufficient_privilege or check_violation or unique_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\nBob wrote a row for Ada';
  end if;
  -- ...and cannot update or delete hers.
  update public.chat_wallpapers set preset_id = 'grid' where user_id = ada;
  delete from public.chat_wallpapers where user_id = ada;
  execute 'reset role';
  if (select count(*) from public.chat_wallpapers where user_id = ada) <> 2 then
    failures := failures || E'\nBob deleted Ada''s rows';
  end if;
  if exists (select 1 from public.chat_wallpapers where user_id = ada and preset_id = 'grid') then
    failures := failures || E'\nBob updated Ada''s rows';
  end if;

  -- A chat you are not in cannot get a wallpaper.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  failed := false;
  begin
    perform public.set_chat_wallpaper(other, 'preset', 'dots');
  exception when insufficient_privilege then failed := true;
  end;
  execute 'reset role';
  if not failed then
    failures := failures || E'\nBob set a wallpaper for a chat he is not in';
  end if;

  -- The photo must be in your own folder, with a plain name.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  failed := false;
  begin
    perform public.set_chat_wallpaper(dm, 'photo', null, ada_photo);
  exception when check_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\nBob pointed at Ada''s photo';
  end if;
  failed := false;
  begin
    perform public.set_chat_wallpaper(dm, 'photo', null, 'x/../' || bob_photo);
  exception when check_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\na path with .. was accepted';
  end if;
  failed := false;
  begin
    perform public.set_chat_wallpaper(dm, 'preset', null);
  exception when check_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\na preset without a name was accepted';
  end if;
  failed := false;
  begin
    perform public.set_chat_wallpaper(dm, 'photo', null, bob_photo, 2.5);
  exception when check_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\na dim above 1 was accepted';
  end if;
  failed := false;
  begin
    perform public.set_chat_wallpaper(dm, 'sticker');
  exception when check_violation then failed := true;
  end;
  if not failed then
    failures := failures || E'\nan unknown kind was accepted';
  end if;
  execute 'reset role';

  -- Anonymous callers can do nothing.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  execute 'set local role anon';
  failed := false;
  begin
    perform public.set_chat_wallpaper(null, 'preset', 'dawn');
  exception when insufficient_privilege then failed := true;
  end;
  execute 'reset role';
  if not failed then
    failures := failures || E'\nanon set a wallpaper';
  end if;

  -- Clearing returns to the default and frees the photo.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  select public.clear_chat_wallpaper(dm) into freed;
  select count(*) into seen from public.chat_wallpapers;
  execute 'reset role';
  if freed is distinct from ada_photo2 then
    failures := failures || format(E'\nclearing freed %s', freed);
  end if;
  if seen <> 1 then
    failures := failures || format(E'\nafter clearing Ada has %s rows', seen);
  end if;

  -- A chat's wallpapers do not outlive the chat.
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  perform public.set_chat_wallpaper(dm, 'none');
  execute 'reset role';
  delete from public.conversations where id = dm;
  if exists (select 1 from public.chat_wallpapers where conversation_id = dm) then
    failures := failures || E'\nwallpapers outlived their chat';
  end if;

  if failures <> '' then
    raise exception 'wallpaper checks failed:%', failures;
  end if;
end $$;

-- Photos: own folder only, plain names.
do $$
declare
  ada uuid := '00000000-0000-4000-8000-0000000000a1';
  bob uuid := '00000000-0000-4000-8000-0000000000b1';
  good text := '00000000-0000-4000-8000-0000000000a1/44444444-4444-4444-8444-444444444444.jpg';
  seen integer;
  failed boolean;
  failures text := '';
begin
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name, owner)
  values ('wallpapers', good, ada);

  -- Not in someone else's folder.
  failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('wallpapers', '00000000-0000-4000-8000-0000000000b1/55555555-5555-4555-8555-555555555555.jpg', ada);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then
    failures := failures || E'\nAda wrote into Bob''s folder';
  end if;

  -- Not with an odd name or a nested path.
  failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('wallpapers', '00000000-0000-4000-8000-0000000000a1/notes.txt', ada);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then
    failures := failures || E'\nan odd file name was accepted';
  end if;
  failed := false;
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('wallpapers', '00000000-0000-4000-8000-0000000000a1/sub/66666666-6666-4666-8666-666666666666.jpg', ada);
  exception when insufficient_privilege then failed := true;
  end;
  if not failed then
    failures := failures || E'\na nested path was accepted';
  end if;

  select count(*) into seen from storage.objects where bucket_id = 'wallpapers';
  execute 'reset role';
  if seen <> 1 then
    failures := failures || format(E'\nAda reads %s of her 1 photos', seen);
  end if;

  -- Bob cannot read, move or remove it. (Storage refuses deletes through
  -- SQL unless told it is on purpose; the policies still apply.)
  perform set_config('storage.allow_delete_query', 'true', true);
  perform pg_temp.as_user(bob);
  execute 'set local role authenticated';
  select count(*) into seen from storage.objects where bucket_id = 'wallpapers';
  update storage.objects
  set name = '00000000-0000-4000-8000-0000000000b1/77777777-7777-4777-8777-777777777777.jpg'
  where bucket_id = 'wallpapers';
  delete from storage.objects where bucket_id = 'wallpapers';
  execute 'reset role';
  if seen <> 0 then
    failures := failures || E'\nBob can read Ada''s photo';
  end if;
  if not exists (select 1 from storage.objects where bucket_id = 'wallpapers' and name = good) then
    failures := failures || E'\nBob moved or removed Ada''s photo';
  end if;

  -- Ada removes her own.
  perform pg_temp.as_user(ada);
  execute 'set local role authenticated';
  delete from storage.objects where bucket_id = 'wallpapers' and name = good;
  execute 'reset role';
  if exists (select 1 from storage.objects where bucket_id = 'wallpapers' and name = good) then
    failures := failures || E'\nAda could not remove her photo';
  end if;

  if failures <> '' then
    raise exception 'photo checks failed:%', failures;
  end if;
end $$;

rollback;
