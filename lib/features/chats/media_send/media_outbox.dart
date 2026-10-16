import 'dart:async';

import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/outbox.dart';

/// Uploads a queued attachment and then stores its message. This is what
/// the outbox engine calls for entries with media.
class MediaSendPipeline {
  MediaSendPipeline({
    required this.store,
    required this.uploader,
    required this.sender,
    required this.progress,
  });

  final PendingMediaStore store;
  final ChatMediaUploader uploader;
  final MediaMessageSender sender;
  final UploadProgressTracker progress;

  final _cancels = <String, UploadCancelToken>{};

  /// Entries whose file the server already has, so a retry after a failed
  /// insert does not send the bytes again.
  final _uploaded = <String>{};

  /// Stops [clientId]'s upload if one is running.
  void cancel(String clientId) {
    _cancels[clientId]?.cancel();
  }

  /// Forgets what is kept for [clientId] (it was sent or dropped).
  Future<void> release(String clientId) async {
    _uploaded.remove(clientId);
    progress.forget(clientId);
    await store.delete(clientId);
  }

  Future<String?> send(OutboxEntry entry) async {
    final media = entry.media;
    if (media == null) {
      throw ArgumentError('Not a media entry');
    }
    final clientId = entry.clientId;
    final path = mediaStoragePath(
      conversationId: entry.conversationId,
      clientId: clientId,
      fileName: media.fileName,
    );
    final token = _cancels[clientId] = UploadCancelToken();
    try {
      if (!_uploaded.contains(clientId)) {
        final length = await store.length(clientId);
        if (length == null) {
          // A StateError is a refusal: trying again would not bring the
          // file back.
          throw StateError('The file to send is no longer there');
        }
        progress.report(clientId, 0);
        await uploader.upload(
          bucket: media.bucket,
          path: path,
          mimeType: media.mimeType,
          length: length,
          data: store.openRead(clientId),
          onProgress: (value) => progress.report(clientId, value),
          cancel: token,
        );
        _uploaded.add(clientId);
      }
      if (token.isCancelled) {
        throw const UploadCancelledException();
      }
      progress.report(clientId, 1);
      return await sender.sendQueuedMediaMessage(
        conversationId: entry.conversationId,
        clientId: clientId,
        type: media.messageType,
        attachment: media.attachmentJson(path),
        body: entry.body,
        attachmentGroupId: media.groupId,
        replyToMessageId: entry.replyToMessageId,
        replyPreview: entry.replyPreview,
        notify: media.notifies,
      );
    } finally {
      _cancels.remove(clientId);
      progress.finish(clientId);
    }
  }
}
