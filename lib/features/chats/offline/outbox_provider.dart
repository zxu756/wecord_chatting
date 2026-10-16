import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_outbox.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/shared/models/message.dart';

/// The current user's messages waiting to be sent, oldest first. Kept in
/// the offline cache so they survive a restart, sent again when the
/// connection returns, and cleared on sign-out.
final outboxProvider = NotifierProvider<OutboxNotifier, List<OutboxEntry>>(
  OutboxNotifier.new,
);

/// Whether the repository can send from the outbox ([OutboxMessageSender]).
final outboxAvailableProvider = Provider<bool>((ref) {
  return ref.watch(chatsRepositoryProvider) is OutboxMessageSender;
});

/// The waiting messages of one conversation.
final conversationOutboxProvider = Provider.autoDispose
    .family<List<OutboxEntry>, String>((ref, conversationId) {
      return [
        for (final entry in ref.watch(outboxProvider))
          if (entry.conversationId == conversationId) entry,
      ];
    });

/// One entry of the outbox by client id, null once it is stored or dropped.
final outboxEntryProvider = Provider.autoDispose.family<OutboxEntry?, String>((
  ref,
  clientId,
) {
  return ref.watch(
    outboxProvider.select((entries) {
      for (final entry in entries) {
        if (entry.clientId == clientId) {
          return entry;
        }
      }
      return null;
    }),
  );
});

/// An attachment to queue: [data] is read once, into the pending media
/// store.
class MediaToQueue {
  const MediaToQueue({
    required this.kind,
    required this.fileName,
    required this.mimeType,
    required this.data,
    this.width,
    this.height,
    this.blurhash,
    this.preview,
  });

  final OutboxMediaKind kind;
  final String fileName;
  final String mimeType;
  final Stream<List<int>> Function() data;
  final int? width;
  final int? height;
  final String? blurhash;

  /// A small picture for the bubble while it uploads.
  final Uint8List? preview;
}

class OutboxNotifier extends Notifier<List<OutboxEntry>> {
  OutboxEngine? _engine;
  MediaSendPipeline? _media;
  PendingMediaStore? _store;

  @override
  List<OutboxEntry> build() {
    final repository = ref.watch(chatsRepositoryProvider);
    final cache = ref.watch(chatCacheProvider);
    // Not watched: the sign-out guard rebuilds the outbox when the user
    // changes (see offline_session.dart).
    final userId = ref.read(authRepositoryProvider).currentUser?.id;
    _engine = null;
    if (repository is! OutboxMessageSender || userId == null) {
      return const [];
    }
    final sender = repository as OutboxMessageSender;
    final store = ref.watch(pendingMediaStoreProvider);
    _store = store;
    late final OutboxEngine engine;
    final media = repository is MediaMessageSender
        ? MediaSendPipeline(
            store: store,
            uploader: ref.watch(chatMediaUploaderProvider),
            sender: repository as MediaMessageSender,
            progress: ref.watch(uploadProgressTrackerProvider),
            albumHasWaiting: (entry) => _albumHasWaiting(engine, entry),
          )
        : null;
    _media = media;
    var knownMedia = <String>{};
    engine = OutboxEngine(
      send: (entry) {
        if (entry.media != null) {
          if (media == null) {
            throw StateError('This server cannot take attachments');
          }
          return media.send(entry);
        }
        return sender.sendQueuedTextMessage(
          conversationId: entry.conversationId,
          clientId: entry.clientId,
          body: entry.body,
          replyToMessageId: entry.replyToMessageId,
          replyPreview: entry.replyPreview,
          mentions: entry.mentions,
        );
      },
      onChanged: (entries) {
        if (!identical(_engine, engine)) {
          return;
        }
        state = entries;
        // Files of attachments that left the outbox (sent, cancelled,
        // discarded) are not needed any more.
        final mediaIds = {
          for (final entry in entries)
            if (entry.media != null) entry.clientId,
        };
        for (final gone in knownMedia.difference(mediaIds)) {
          unawaited(media?.release(gone));
        }
        knownMedia = mediaIds;
        unawaited(
          cache
              .writeOutbox(userId, [
                for (final entry in entries)
                  // Without files kept on disk, an attachment cannot
                  // outlive the app.
                  if (entry.media == null || store.persistent) entry.toJson(),
              ])
              .catchError((Object _) {}),
        );
      },
      onSent: (entry, messageId) async {
        final thread = chatThreadProvider(entry.conversationId);
        if (messageId != null && ref.exists(thread)) {
          await ref.read(thread.notifier).ingestSent(messageId);
        }
      },
    );
    _engine = engine;
    ref.onDispose(engine.dispose);
    engine.setOnline(ref.read(deviceConnectivityProvider).value ?? true);
    ref.listen<bool>(
      deviceConnectivityProvider.select((value) => value.value ?? true),
      (previous, online) {
        engine.setOnline(online);
        if (online) {
          unawaited(engine.drain());
        }
      },
    );
    unawaited(_restore(engine, cache, userId));
    return const [];
  }

  /// Whether other attachments of [entry]'s album are still due to be sent.
  static bool _albumHasWaiting(OutboxEngine engine, OutboxEntry entry) {
    final groupId = entry.media?.groupId;
    if (groupId == null) {
      return false;
    }
    return engine.entries.any(
      (other) =>
          other.clientId != entry.clientId &&
          other.media?.groupId == groupId &&
          other.state == OutboxState.sending,
    );
  }

  Future<void> _restore(
    OutboxEngine engine,
    ChatCache cache,
    String userId,
  ) async {
    try {
      final saved = await cache.readOutbox(userId);
      final store = _store;
      final kept = <OutboxEntry>[];
      for (final json in saved) {
        final entry = _tryEntry(json);
        if (entry == null) {
          continue;
        }
        // An attachment whose file is gone cannot be sent.
        if (entry.media != null &&
            (store == null || await store.length(entry.clientId) == null)) {
          continue;
        }
        kept.add(entry);
      }
      if (!identical(_engine, engine)) {
        return;
      }
      if (kept.isNotEmpty) {
        engine.restore(kept);
        unawaited(engine.drain());
      }
      // Files nothing in the outbox points at (a crash between steps).
      if (store != null) {
        final wanted = {for (final entry in kept) entry.clientId};
        for (final id in await store.clientIds()) {
          if (!wanted.contains(id) && engine.entry(id) == null) {
            await store.delete(id);
          }
        }
      }
    } catch (_) {
      // Nothing kept.
    }
  }

  static OutboxEntry? _tryEntry(Map<String, dynamic> json) {
    try {
      return OutboxEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Whether messages go through the outbox (a signed-in user and a
  /// repository that sends with client ids).
  bool get isAvailable => _engine != null;

  /// Queues a text message; it shows as sending at once. Call [sendNow]
  /// to try it straight away.
  OutboxEntry? enqueue({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const [],
  }) {
    final engine = _engine;
    if (engine == null) {
      return null;
    }
    return engine.enqueue(
      OutboxEntry(
        clientId: newClientId(),
        conversationId: conversationId,
        body: body,
        createdAt: DateTime.now().toUtc(),
        replyToMessageId: replyToMessageId,
        replyPreview: replyPreview,
        mentions: mentions,
      ),
    );
  }

  /// Queues pictures, videos and files to send, in order. They share an
  /// album when there is more than one; [caption] goes with the first. The
  /// files are copied into the pending media store first, so the sender can
  /// close the app. Call [startSending] afterwards.
  Future<List<OutboxEntry>> enqueueMedia({
    required String conversationId,
    required List<MediaToQueue> items,
    String caption = '',
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  }) async {
    final engine = _engine;
    final store = _store;
    if (engine == null || store == null || items.isEmpty) {
      return const [];
    }
    final groupId = items.length > 1 ? newClientId() : null;
    final createdAt = DateTime.now().toUtc();
    final entries = <OutboxEntry>[];
    try {
      for (final (index, item) in items.indexed) {
        final clientId = newClientId();
        final size = await store.put(clientId, item.data());
        final preview = item.preview;
        if (preview != null) {
          await store.putPreview(clientId, preview);
        }
        entries.add(
          OutboxEntry(
            clientId: clientId,
            conversationId: conversationId,
            body: index == 0 ? caption : '',
            // Kept in order even when the clock does not move.
            createdAt: createdAt.add(Duration(microseconds: index)),
            replyToMessageId: index == 0 ? replyToMessageId : null,
            replyPreview: index == 0 ? replyPreview : null,
            media: OutboxMedia(
              kind: item.kind,
              fileName: item.fileName,
              mimeType: item.mimeType,
              size: size,
              width: item.width,
              height: item.height,
              blurhash: item.blurhash,
              groupId: groupId,
              groupIndex: index,
              hasPreview: preview != null,
            ),
          ),
        );
      }
    } catch (_) {
      for (final entry in entries) {
        await store.delete(entry.clientId);
      }
      rethrow;
    }
    for (final entry in entries) {
      engine.enqueue(entry);
    }
    return entries;
  }

  /// Starts sending what is waiting, oldest first.
  Future<void> startSending() => _engine?.drain() ?? Future.value();

  /// The reader stopped an attachment: its upload is aborted and it leaves
  /// the chat.
  void cancelMedia(String clientId) {
    _media?.cancel(clientId);
    _engine?.discard(clientId);
  }

  /// Tries every failed attachment of [entry]'s album again (or just
  /// [entry] when it is not in one).
  Future<void> retryMedia(OutboxEntry entry) async {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    final groupId = entry.media?.groupId;
    final failed = [
      for (final other in engine.entries)
        if (other.state == OutboxState.failed &&
            (other.clientId == entry.clientId ||
                (groupId != null && other.media?.groupId == groupId)))
          other,
    ];
    for (final other in failed) {
      engine.reset(other.clientId);
    }
    await engine.drain();
  }

  /// Drops [entry] and, for an album, the rest of its failed attachments.
  void discardMedia(OutboxEntry entry) {
    final engine = _engine;
    if (engine == null) {
      return;
    }
    final groupId = entry.media?.groupId;
    for (final other in engine.entries.toList()) {
      if (other.clientId == entry.clientId ||
          (groupId != null &&
              other.media?.groupId == groupId &&
              other.state == OutboxState.failed)) {
        cancelMedia(other.clientId);
      }
    }
  }

  /// "Edit and resend": puts the failed attachments of [entry]'s album (or
  /// just [entry]) back in the tray of its conversation, with the caption,
  /// and drops them from the outbox. What was already stored stays sent.
  Future<void> editAndResendMedia(OutboxEntry entry) async {
    final engine = _engine;
    final store = _store;
    if (engine == null || store == null || entry.media == null) {
      return;
    }
    final groupId = entry.media?.groupId;
    final failed = [
      for (final other in engine.entries)
        if (other.media != null &&
            other.state == OutboxState.failed &&
            (other.clientId == entry.clientId ||
                (groupId != null && other.media?.groupId == groupId)))
          other,
    ]..sort((a, b) => a.media!.groupIndex.compareTo(b.media!.groupIndex));
    final files = <XFile>[];
    var caption = '';
    for (final item in failed) {
      final media = item.media!;
      try {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in store.openRead(item.clientId)) {
          builder.add(chunk);
        }
        files.add(
          XFile.fromData(
            builder.takeBytes(),
            name: media.fileName,
            mimeType: media.mimeType,
          ),
        );
        if (caption.isEmpty) {
          caption = item.body;
        }
      } catch (_) {
        // The file is gone; the rest still go back.
      }
    }
    discardMedia(entry);
    if (files.isNotEmpty) {
      await ref
          .read(mediaTrayProvider(entry.conversationId).notifier)
          .restore(files, caption: caption);
    }
  }

  Future<OutboxAttempt> sendNow(String clientId) {
    final engine = _engine;
    if (engine == null) {
      return Future.value(const OutboxSent(null));
    }
    return engine.sendNow(clientId);
  }

  /// Sends a failed message again (the reader tapped it).
  Future<OutboxAttempt> retry(String clientId) {
    final engine = _engine;
    if (engine == null) {
      return Future.value(const OutboxSent(null));
    }
    return engine.retry(clientId);
  }

  void discard(String clientId) => _engine?.discard(clientId);
}
