import 'dart:async';

import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_search/local_search_index.dart';

/// A [ChatCache] that keeps the offline search index (L3) in step with what
/// the cache holds. Every way the cache forgets a message already passes
/// through it (the chat page writing the newest messages after a recall, the
/// expiry sweep, clearing a chat or the whole cache, signing out), so the
/// index needs no sync points of its own: it is written from the same rows
/// and emptied at the same moment.
///
/// What the index does not take: deleted (recalled) messages, messages held
/// back or removed by the circle's AI guard, expired ones, photos and videos
/// that open once (see `searchableTextOfRow`).
class IndexedChatCache implements ChatCache {
  IndexedChatCache(this.inner, this.index, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ChatCache inner;
  final LocalSearchIndex index;
  final DateTime Function() _clock;

  @override
  Future<List<Map<String, dynamic>>?> readConversations(String userId) =>
      inner.readConversations(userId);

  @override
  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) => inner.writeConversations(userId, rows);

  @override
  Future<List<Map<String, dynamic>>> readMessages(
    String userId,
    String conversationId,
  ) => inner.readMessages(userId, conversationId);

  @override
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) async {
    await inner.writeMessages(userId, conversationId, rows);
    final kept = rows.length <= cachedMessagesPerConversation
        ? rows
        : rows.sublist(rows.length - cachedMessagesPerConversation);
    try {
      await index.replace(
        userId,
        conversationId,
        ConversationIndex.fromRows(kept, _clock().toUtc()),
      );
    } on Object {
      // The index is a convenience; the next write tries again.
    }
  }

  @override
  Future<List<Map<String, dynamic>>> readOutbox(String userId) =>
      inner.readOutbox(userId);

  @override
  Future<void> writeOutbox(String userId, List<Map<String, dynamic>> entries) =>
      inner.writeOutbox(userId, entries);

  /// The cache's own count, and the index's share added to the chat it is
  /// for, so the storage page shows what a chat really takes here.
  @override
  Future<ChatCacheSizes> measure(String userId) async {
    final sizes = await inner.measure(userId);
    try {
      final indexed = await index.sizes(userId);
      if (indexed.isEmpty) {
        return sizes;
      }
      final messages = {...sizes.messages};
      for (final entry in indexed.entries) {
        messages[entry.key] = (messages[entry.key] ?? 0) + entry.value;
      }
      return ChatCacheSizes(
        conversationList: sizes.conversationList,
        outbox: sizes.outbox,
        messages: messages,
      );
    } on Object {
      return sizes;
    }
  }

  @override
  Future<void> removeMessages(
    String userId,
    String conversationId, {
    Set<String>? ids,
  }) async {
    // The index first: what it lost cannot be found again, while a failed
    // removal in the cache is tried again and does no harm in between.
    try {
      if (ids == null) {
        await index.removeConversation(userId, conversationId);
      } else {
        await index.removeMessages(userId, conversationId, ids);
      }
    } on Object {
      // Still removed from the cache below.
    }
    await inner.removeMessages(userId, conversationId, ids: ids);
  }

  @override
  Future<void> clearMessages(String userId) async {
    try {
      await index.clearUser(userId);
    } on Object {
      // Still cleared from the cache below.
    }
    await inner.clearMessages(userId);
  }

  @override
  Future<List<Map<String, dynamic>>> removeExpired(
    String userId,
    DateTime now,
  ) async {
    final removed = await inner.removeExpired(userId, now);
    final byConversation = <String, Set<String>>{};
    for (final row in removed) {
      final conversationId = row['conversation_id'];
      final id = row['id'];
      if (conversationId is String && id is String) {
        (byConversation[conversationId] ??= {}).add(id);
      }
    }
    for (final entry in byConversation.entries) {
      try {
        await index.removeMessages(userId, entry.key, entry.value);
      } on Object {
        // The index also drops expired messages whenever it is rebuilt.
      }
    }
    return removed;
  }

  @override
  Future<void> clear() async {
    try {
      await index.clear();
    } on Object {
      // Still cleared from the cache below.
    }
    await inner.clear();
  }

  /// Indexes the conversations the cache holds that the index does not know
  /// yet (a cache from before the search, or one the index lost), one
  /// conversation at a time with [pause] between, and forgets index entries
  /// of conversations the cache no longer holds. Returns how many
  /// conversations were indexed.
  Future<int> backfill(
    String userId, {
    Future<void> Function()? pause,
    bool Function()? shouldStop,
  }) async {
    final cached = (await inner.measure(userId)).messages.keys.toSet();
    final known = await index.indexedConversations(userId);
    for (final stale in known.difference(cached)) {
      await index.removeConversation(userId, stale);
    }
    var indexed = 0;
    for (final conversationId in cached.difference(known)) {
      if (shouldStop?.call() ?? false) {
        break;
      }
      final version = index.versionOf(userId, conversationId);
      final rows = await inner.readMessages(userId, conversationId);
      await index.replaceIfUnchanged(
        userId,
        conversationId,
        ConversationIndex.fromRows(rows, _clock().toUtc()),
        version,
      );
      indexed++;
      await pause?.call();
    }
    return indexed;
  }
}
