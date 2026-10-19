-- L8 accessibility 2.0: a picture can carry a description written by its
-- sender (`attachment.alt`), read aloud by screen readers.
--
-- The description lives in the attachment's JSON, like the BlurHash does, so
-- nothing about the messages table changes: a message insert, a plain forward
-- and an edit all keep whatever the attachment holds. The one place that
-- copies only the keys it knows is the merged forward (a bundle of messages
-- sent as one), which the description would otherwise be dropped from. This
-- redefines just that helper, from its only earlier version
-- (202610180070_merged_forward.sql), with 'alt' added to the kept keys and
-- the description capped at 1000 characters like the app caps it.

create or replace function public.merged_forward_attachment(att jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when att is null
      or jsonb_typeof(att) <> 'object'
      or att->>'bucket' is null
      or att->>'path' is null
      or att->>'bucket' not in ('chat-images', 'voice-messages', 'chat-files')
    then null
    else (
      select jsonb_object_agg(
        e.key,
        case
          when e.key = 'alt' and jsonb_typeof(e.value) = 'string'
            then to_jsonb(left(e.value #>> '{}', 1000))
          else e.value
        end
      )
      from jsonb_each(att) e
      where e.key in (
        'kind', 'bucket', 'path', 'name', 'mime_type', 'size',
        'width', 'height', 'blurhash', 'duration_ms', 'alt'
      )
      -- A description that is not text is left behind.
      and (e.key <> 'alt' or jsonb_typeof(e.value) = 'string')
    )
  end;
$$;

revoke execute on function public.merged_forward_attachment(jsonb)
  from public, anon, authenticated;
