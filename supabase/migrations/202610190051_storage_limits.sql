-- Size and type limits on the storage buckets people upload to.
--
-- Until now only chat-files (50 MB) had a limit, and no bucket had a list of
-- allowed types, so anyone signed in could store anything of any size in a
-- picture bucket and have it served back as an "image". The limits below are
-- what the app already sends and no more:
--
--   chat-files       50 MB (maxChatFileBytes in chats_repository.dart, which
--                    the media tray, the file picker and the outbox check
--                    before they upload). Any type: files, videos and SVG
--                    pictures go here.
--   chat-images      50 MB, the same ceiling the tray applies to a picture
--                    before it is scaled; pictures are scaled to 2560 px and
--                    re-encoded as JPEG (HEIC and BMP become JPEG), but GIF,
--                    WebP, AVIF, PNG and "original quality" are sent as
--                    they are. No SVG: the app sends SVG as a file.
--   chat-media       as chat-images (pictures of circle posts).
--   voice-messages   50 MB. The recorder writes 16-bit mono 44.1 kHz WAV,
--                    about 5.3 MB a minute, so that is about nine minutes.
--                    The other types are those the app can play.
--   profile-avatars, group-avatars, profile-banners: 20 MB; the app picks
--                    from the photo library and does not scale these.
--                    Pictures only.
--
-- Storage compares the Content-Type the upload names with the list; an
-- upload over the size is refused (413), one of another type too (415).
-- Files already stored are not touched.

update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = array[
      'image/jpeg', 'image/jpg', 'image/pjpeg', 'image/png', 'image/gif',
      'image/webp', 'image/heic', 'image/heif', 'image/heic-sequence',
      'image/heif-sequence', 'image/avif', 'image/bmp', 'image/x-ms-bmp',
      'image/tiff', 'image/x-icon', 'image/vnd.microsoft.icon'
    ]
where id in ('chat-images', 'chat-media');

update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = null
where id = 'chat-files';

update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = array[
      'audio/wav', 'audio/wave', 'audio/x-wav', 'audio/vnd.wave',
      'audio/pcm', 'audio/l16', 'audio/mpeg', 'audio/mp4', 'audio/x-m4a',
      'audio/m4a', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/opus'
    ]
where id = 'voice-messages';

update storage.buckets
set file_size_limit = 20971520,
    allowed_mime_types = array[
      'image/jpeg', 'image/jpg', 'image/pjpeg', 'image/png', 'image/gif',
      'image/webp', 'image/heic', 'image/heif', 'image/avif', 'image/bmp'
    ]
where id in ('profile-avatars', 'group-avatars', 'profile-banners');
