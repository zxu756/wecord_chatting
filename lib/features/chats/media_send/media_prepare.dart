import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';

/// Turns the tray's drafts into attachments for the outbox, in order.
///
/// Pictures are scaled, re-encoded and cleaned of metadata (see
/// [preparePhoto]; [original] skips the scaling and re-compression) and get
/// their size and BlurHash; videos and files are passed on as they are and
/// read from disk only when queued. [onProgress] hears how many are done.
Future<List<MediaToQueue>> prepareDrafts(
  List<DraftAttachment> drafts, {
  required bool original,
  void Function(int done, int total)? onProgress,
}) async {
  final items = <MediaToQueue>[];
  onProgress?.call(0, drafts.length);
  for (final draft in drafts) {
    items.add(await _prepare(draft, original: original));
    onProgress?.call(items.length, drafts.length);
  }
  return items;
}

Future<MediaToQueue> _prepare(
  DraftAttachment draft, {
  required bool original,
}) async {
  switch (draft.kind) {
    case DraftKind.image:
      final bytes = await draft.file.readAsBytes();
      final prepared = await preparePhoto(
        bytes: bytes,
        fileName: draft.name,
        mimeType: draft.mimeType,
        original: original,
      );
      return MediaToQueue(
        kind: OutboxMediaKind.image,
        fileName: prepared.fileName,
        mimeType: prepared.mimeType,
        data: () => Stream.value(prepared.bytes),
        width: prepared.width > 0 ? prepared.width : draft.width,
        height: prepared.height > 0 ? prepared.height : draft.height,
        blurhash: prepared.blurhash,
        preview: draft.thumbnail ?? await makeThumbnail(prepared.bytes),
        original: () => Stream.value(bytes),
        originalFileName: draft.name,
        originalMimeType: draft.mimeType,
        originalQuality: original,
        alt: draft.alt,
      );
    case DraftKind.video:
      final poster = draft.thumbnail;
      return MediaToQueue(
        kind: OutboxMediaKind.video,
        fileName: draft.name,
        mimeType: draft.mimeType,
        data: draft.file.openRead,
        width: draft.width,
        height: draft.height,
        blurhash: poster == null ? null : await photoBlurHash(poster),
        preview: poster,
        originalQuality: original,
      );
    case DraftKind.file:
      return MediaToQueue(
        kind: OutboxMediaKind.file,
        fileName: draft.name,
        mimeType: draft.mimeType,
        data: draft.file.openRead,
        originalQuality: original,
      );
  }
}
