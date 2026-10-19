import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many of a conversation's newest messages the cache keeps.
const cachedMessagesPerConversation = 100;

/// The offline copy of the signed-in user's chats: the conversation list,
/// each conversation's newest messages and the outbox, as the raw rows the
/// server sent. Everything is kept per user and wiped on sign-out.
///
/// Reads answer null or empty when nothing is cached; failures are the
/// caller's to ignore (the cache only ever speeds things up).
abstract interface class ChatCache {
  Future<List<Map<String, dynamic>>?> readConversations(String userId);

  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  );

  /// Oldest first.
  Future<List<Map<String, dynamic>>> readMessages(
    String userId,
    String conversationId,
  );

  /// Replaces the cached messages of [conversationId] with [rows] (oldest
  /// first; the newest [cachedMessagesPerConversation] are kept).
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  );

  Future<List<Map<String, dynamic>>> readOutbox(String userId);

  Future<void> writeOutbox(String userId, List<Map<String, dynamic>> entries);

  /// What [userId]'s offline copy takes, in bytes: the conversation list,
  /// each conversation's messages and the outbox.
  Future<ChatCacheSizes> measure(String userId);

  /// Forgets cached messages of [conversationId]: just [ids], or all of
  /// them when [ids] is null. The conversation list and the outbox stay.
  Future<void> removeMessages(
    String userId,
    String conversationId, {
    Set<String>? ids,
  });

  /// Forgets the conversation list and every conversation's cached
  /// messages, but not the outbox (messages that are still waiting to be
  /// sent are not a cache).
  Future<void> clearMessages(String userId);

  /// Forgets the cached messages that have expired by [now] (disappearing
  /// messages) and returns their rows, so what was kept for them can go too.
  Future<List<Map<String, dynamic>>> removeExpired(String userId, DateTime now);

  /// Forgets everything, for every user.
  Future<void> clear();
}

/// How many bytes a user's offline copy of chats takes.
class ChatCacheSizes {
  const ChatCacheSizes({
    this.conversationList = 0,
    this.outbox = 0,
    this.messages = const {},
  });

  final int conversationList;
  final int outbox;

  /// Bytes of cached messages by conversation id.
  final Map<String, int> messages;

  int get messagesTotal => messages.values.fold(0, (sum, size) => sum + size);

  /// What clearing the cache would free: not the outbox.
  int get clearable => conversationList + messagesTotal;
}

/// Whether a cached message row has expired by [now] (a disappearing
/// message whose time is up).
bool cachedRowExpired(Map<String, dynamic> row, DateTime now) {
  final value = row['expires_at'];
  if (value is! String) {
    return false;
  }
  final expiresAt = DateTime.tryParse(value);
  return expiresAt != null && !expiresAt.isAfter(now);
}

/// The cache the app uses. Off by default (tests and platforms without
/// storage); the app's bootstrap opens the platform's store.
final chatCacheProvider = Provider<ChatCache>((ref) => const NoChatCache());

/// Keeps nothing.
class NoChatCache implements ChatCache {
  const NoChatCache();

  @override
  Future<List<Map<String, dynamic>>?> readConversations(String userId) async =>
      null;

  @override
  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> readMessages(
    String userId,
    String conversationId,
  ) async => const [];

  @override
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) async {}

  @override
  Future<List<Map<String, dynamic>>> readOutbox(String userId) async =>
      const [];

  @override
  Future<void> writeOutbox(
    String userId,
    List<Map<String, dynamic>> entries,
  ) async {}

  @override
  Future<ChatCacheSizes> measure(String userId) async => const ChatCacheSizes();

  @override
  Future<void> removeMessages(
    String userId,
    String conversationId, {
    Set<String>? ids,
  }) async {}

  @override
  Future<void> clearMessages(String userId) async {}

  @override
  Future<List<Map<String, dynamic>>> removeExpired(
    String userId,
    DateTime now,
  ) async => const [];

  @override
  Future<void> clear() async {}
}

/// Strings by key: what the web cache (IndexedDB) and the in-memory cache
/// keep.
abstract interface class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<List<String>> keys();

  Future<void> clear();
}

class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<void> clear() async => values.clear();
}

/// A [ChatCache] over a [KeyValueStore], one JSON document per list.
class KeyValueChatCache implements ChatCache {
  KeyValueChatCache(this.store);

  /// An in-memory cache (tests, and a fallback when storage fails to open).
  factory KeyValueChatCache.memory() =>
      KeyValueChatCache(MemoryKeyValueStore());

  final KeyValueStore store;

  static String _conversationsKey(String userId) => 'u/$userId/conversations';

  static String _messagesKey(String userId, String conversationId) =>
      'u/$userId/messages/$conversationId';

  static String _outboxKey(String userId) => 'u/$userId/outbox';

  Future<List<Map<String, dynamic>>?> _readList(String key) async {
    final text = await store.read(key);
    if (text == null) {
      return null;
    }
    final decoded = jsonDecode(text);
    if (decoded is! List) {
      return null;
    }
    return [
      for (final item in decoded)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>?> readConversations(String userId) {
    return _readList(_conversationsKey(userId));
  }

  @override
  Future<void> writeConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) {
    return store.write(_conversationsKey(userId), jsonEncode(rows));
  }

  @override
  Future<List<Map<String, dynamic>>> readMessages(
    String userId,
    String conversationId,
  ) async {
    return await _readList(_messagesKey(userId, conversationId)) ?? const [];
  }

  @override
  Future<void> writeMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) {
    final kept = rows.length <= cachedMessagesPerConversation
        ? rows
        : rows.sublist(rows.length - cachedMessagesPerConversation);
    return store.write(_messagesKey(userId, conversationId), jsonEncode(kept));
  }

  @override
  Future<List<Map<String, dynamic>>> readOutbox(String userId) async {
    return await _readList(_outboxKey(userId)) ?? const [];
  }

  @override
  Future<void> writeOutbox(String userId, List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) {
      return store.delete(_outboxKey(userId));
    }
    return store.write(_outboxKey(userId), jsonEncode(entries));
  }

  static int _bytes(String text) => utf8.encode(text).length;

  @override
  Future<ChatCacheSizes> measure(String userId) async {
    final messagesPrefix = _messagesKey(userId, '');
    final messages = <String, int>{};
    for (final key in await store.keys()) {
      if (!key.startsWith(messagesPrefix)) {
        continue;
      }
      final text = await store.read(key);
      if (text != null) {
        messages[key.substring(messagesPrefix.length)] = _bytes(text);
      }
    }
    final conversations = await store.read(_conversationsKey(userId));
    final outbox = await store.read(_outboxKey(userId));
    return ChatCacheSizes(
      conversationList: conversations == null ? 0 : _bytes(conversations),
      outbox: outbox == null ? 0 : _bytes(outbox),
      messages: messages,
    );
  }

  @override
  Future<void> removeMessages(
    String userId,
    String conversationId, {
    Set<String>? ids,
  }) async {
    final key = _messagesKey(userId, conversationId);
    if (ids == null) {
      return store.delete(key);
    }
    final rows = await _readList(key);
    if (rows == null) {
      return;
    }
    final kept = [
      for (final row in rows)
        if (!ids.contains(row['id'])) row,
    ];
    if (kept.length == rows.length) {
      return;
    }
    return kept.isEmpty
        ? store.delete(key)
        : store.write(key, jsonEncode(kept));
  }

  @override
  Future<void> clearMessages(String userId) async {
    final prefix = _messagesKey(userId, '');
    for (final key in await store.keys()) {
      if (key.startsWith(prefix)) {
        await store.delete(key);
      }
    }
    await store.delete(_conversationsKey(userId));
  }

  @override
  Future<List<Map<String, dynamic>>> removeExpired(
    String userId,
    DateTime now,
  ) async {
    final prefix = _messagesKey(userId, '');
    final removed = <Map<String, dynamic>>[];
    for (final key in await store.keys()) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final rows = await _readList(key);
      if (rows == null) {
        continue;
      }
      final kept = <Map<String, dynamic>>[];
      for (final row in rows) {
        (cachedRowExpired(row, now) ? removed : kept).add(row);
      }
      if (kept.length == rows.length) {
        continue;
      }
      if (kept.isEmpty) {
        await store.delete(key);
      } else {
        await store.write(key, jsonEncode(kept));
      }
    }
    return removed;
  }

  @override
  Future<void> clear() => store.clear();
}

/// Runs [write] at most every [delay] per key, with the latest value.
class CacheWriteScheduler {
  CacheWriteScheduler({this.delay = const Duration(milliseconds: 400)});

  final Duration delay;
  final _timers = <String, Timer>{};
  final _pending = <String, Future<void> Function()>{};

  void schedule(String key, Future<void> Function() write) {
    _pending[key] = write;
    _timers[key] ??= Timer(delay, () => unawaited(_flush(key)));
  }

  Future<void> _flush(String key) async {
    _timers.remove(key);
    final write = _pending.remove(key);
    if (write == null) {
      return;
    }
    try {
      await write();
    } catch (_) {
      // The cache only speeds things up.
    }
  }

  /// Writes everything scheduled now.
  Future<void> flushAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    final keys = [..._pending.keys];
    _timers.clear();
    for (final key in keys) {
      await _flush(key);
    }
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
  }
}
