import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_repository.dart';
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

class OutboxNotifier extends Notifier<List<OutboxEntry>> {
  OutboxEngine? _engine;

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
    late final OutboxEngine engine;
    engine = OutboxEngine(
      send: (entry) => sender.sendQueuedTextMessage(
        conversationId: entry.conversationId,
        clientId: entry.clientId,
        body: entry.body,
        replyToMessageId: entry.replyToMessageId,
        replyPreview: entry.replyPreview,
        mentions: entry.mentions,
      ),
      onChanged: (entries) {
        if (!identical(_engine, engine)) {
          return;
        }
        state = entries;
        unawaited(
          cache
              .writeOutbox(userId, [
                for (final entry in entries) entry.toJson(),
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
    engine.setOnline(ref.read(deviceConnectivityProvider).valueOrNull ?? true);
    ref.listen<bool>(
      deviceConnectivityProvider.select((value) => value.valueOrNull ?? true),
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

  Future<void> _restore(
    OutboxEngine engine,
    ChatCache cache,
    String userId,
  ) async {
    try {
      final saved = await cache.readOutbox(userId);
      if (!identical(_engine, engine) || saved.isEmpty) {
        return;
      }
      engine.restore([
        for (final json in saved)
          if (_tryEntry(json) case final entry?) entry,
      ]);
      unawaited(engine.drain());
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
