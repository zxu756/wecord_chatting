-- Round video messages (roadmap A13): what the server checks.
--
-- A round video message ("video note") is an ordinary video file message (type
-- 'file', attachment kind 'video', stored in chat-files like any video) whose
-- attachment also says
--     "video_note": true, "duration_ms": <milliseconds>
-- The roadmap sketched kind 'video_note'; the flag is used instead because
-- everything that already reads kind 'video' (the conversation list's
-- "Video", the push text "[Video]" in claim_push_delivery, chat media, search,
-- forwarding, the album counts) keeps working without being rewritten, and an
-- older app simply shows the note as a video.
--
-- The limits, so a client cannot make a "note" that is a movie:
--   * at most 60 seconds (a second of slack for the recorder's last frame),
--     at least 0.5 s;
--   * at most 30 MB (the app records about 480 px, a minute is 5-10 MB; the
--     bucket's own ceiling is 50 MB);
--   * a video type, and never a member of an album (view-once is allowed: the
--     view-once viewer shows it);
--   * duration_ms and size are whole numbers; anything else on the flag is
--     refused.
-- Checked on insert only; the attachment cannot be edited afterwards.

create or replace function public.messages_check_video_note()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  attachment jsonb := new.attachment;
  duration_text text;
  size_text text;
begin
  if attachment is null
    or jsonb_typeof(attachment) <> 'object'
    or not (attachment ? 'video_note')
  then
    return new;
  end if;

  if attachment->'video_note' <> 'true'::jsonb then
    raise exception 'Invalid video message' using errcode = '22023';
  end if;
  if new.type <> 'file'
    or attachment->>'kind' is distinct from 'video'
    or coalesce(attachment->>'mime_type', '') not like 'video/%'
    or new.attachment_group_id is not null
  then
    raise exception 'Invalid video message' using errcode = '22023';
  end if;

  duration_text := attachment->>'duration_ms';
  size_text := attachment->>'size';
  if duration_text is null or duration_text !~ '^[0-9]{1,6}$'
    or size_text is null or size_text !~ '^[0-9]{1,10}$'
  then
    raise exception 'Invalid video message' using errcode = '22023';
  end if;
  if duration_text::integer < 500 or duration_text::integer > 61000 then
    raise exception 'A video message can be at most 60 seconds'
      using errcode = '22023';
  end if;
  if size_text::bigint < 1 or size_text::bigint > 31457280 then
    raise exception 'This video message is too large'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke execute on function public.messages_check_video_note()
  from public, anon, authenticated;

drop trigger if exists messages_check_video_note on public.messages;
create trigger messages_check_video_note
  before insert on public.messages
  for each row execute function public.messages_check_video_note();
