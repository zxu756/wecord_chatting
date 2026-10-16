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
    this.albumHasWaiting = _never,
  });

  final PendingMediaStore store;
  final ChatMediaUploader uploader;
  final MediaMessageSender sender;
  final UploadProgressTracker progress;

  /// Whether other attachments of [entry]'s album are still waiting to be
  /// sent, so [entry] is not the last one.
  final bool Function(OutboxEntry entry) albumHasWaiting;

  final _cancels = <String, UploadCancelToken>{};

  /// Entries whose file the server already has, so a retry after a failed
  /// insert does not send the bytes again.
  final _uploaded = <String>{};

  /// The latest stored message of each album that has not sent its push
  /// yet, by album id.
  final _albumSent = <String, String>{};

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

  /// The last attachment of an album was refused or stopped: the ones
  /// stored before it sent no push (they expected it to), so push for them
  /// now. A failure that will be tried again leaves it to that try.
  Future<void> _notifyStoredPartOfAlbum(OutboxEntry entry, Object error) async {
    final groupId = entry.media?.groupId;
    if (groupId == null || !isSendRefusal(error) || albumHasWaiting(entry)) {
      return;
    }
    final stored = _albumSent.remove(groupId);
    if (stored == null) {
      return;
    }
    try {
      await sender.notifyMessageSent(stored);
    } catch (_) {
      // Push is a courtesy.
    }
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
          throw PendingMediaMissingException();
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
      // An album sends one push, once all of it is stored, so that it can
      // say what it holds ("sent 3 photos").
      final groupId = media.groupId;
      final notify = groupId == null || !albumHasWaiting(entry);
      final messageId = await sender.sendQueuedMediaMessage(
        conversationId: entry.conversationId,
        clientId: clientId,
        type: media.messageType,
        attachment: media.attachmentJson(path),
        body: entry.body,
        attachmentGroupId: groupId,
        replyToMessageId: entry.replyToMessageId,
        replyPreview: entry.replyPreview,
        notify: notify,
      );
      if (groupId != null) {
        if (notify) {
          _albumSent.remove(groupId);
        } else if (messageId != null) {
          _albumSent[groupId] = messageId;
        }
      }
      return messageId;
    } catch (error) {
      await _notifyStoredPartOfAlbum(entry, error);
      rethrow;
    } finally {
      _cancels.remove(clientId);
      progress.finish(clientId);
    }
  }
}

bool _never(OutboxEntry entry) => false;
