-- Media channels and Q&A channels (roadmap C9), part 3 of 4: media channels
-- need a picture.
--
-- A media channel (kind 'media') is a forum whose posts are shown as a wall of
-- pictures, so every post needs one: create_forum_post refuses a post in a
-- media channel without an image. Everything else about posting is the
-- forum's, and it all still applies to the post's first message because that
-- message is inserted the same way: the channel's send_messages permission and
-- overwrites, timeouts, bans, raid protection (C6), the AI guard (including
-- its picture check, F7), AutoMod, locks (C5), K1 and the storage rule
-- (the image must sit under the channel's conversation folder).
--
-- create_forum_post is patched in place from its current definition (the
-- quiet AutoMod refusal of 202610160035, mentions, and so on stay).

do $patch$
declare
  target record;
  found_any boolean := false;
  original text;
  patched text;
begin
  for target in
    select p.oid
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'create_forum_post'
  loop
    found_any := true;
    original := pg_get_functiondef(target.oid);
    patched := replace(
      original,
      '  if char_length(trimmed_body) = 0 and post_attachment is null then',
      '  if channel.kind = ''media'' and post_attachment is null then' || E'\n'
        || '    raise exception ''A post in a media channel needs a picture''' || E'\n'
        || '      using errcode = ''22023'';' || E'\n'
        || '  end if;' || E'\n\n'
        || '  if char_length(trimmed_body) = 0 and post_attachment is null then'
    );
    if patched = original then
      if original !~ 'needs a picture' then
        raise exception 'create_forum_post has no body check to put the picture check before';
      end if;
    else
      execute patched;
    end if;
  end loop;
  if not found_any then
    raise exception 'create_forum_post does not exist';
  end if;
end;
$patch$;
