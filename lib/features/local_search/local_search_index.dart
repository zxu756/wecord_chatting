import 'dart:async';
import 'dart:convert';

import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/local_search/search_text.dart';

/// One message the offline search can find.
class IndexedMessage {
  IndexedMessage({
    required this.id,
    required this.createdAtMs,
    required this.senderId,
    required this.text,
    this.hasMask = 0,
    this.pinned = false,
    this.mentionIds = const [],
  });

  factory IndexedMessage.fromJson(List<dynamic> json) {
    return IndexedMessage(
      id: json[0] as String,
      createdAtMs: (json[1] as num).toInt(),
      senderId: json[2] as String,
      hasMask: (json[3] as num).toInt(),
      pinned: json[4] == 1,
      text: json[5] as String,
      mentionIds: [
        for (final id in json.length > 6 ? json[6] as List<dynamic> : const [])
          id as String,
      ],
    );
  }

  /// The row of a cached message, or null when it must not be searchable
  /// (see [searchableTextOfRow]).
  static IndexedMessage? fromRow(Map<String, dynamic> row, DateTime now) {
    final id = row['id'];
    final senderId = row['sender_id'];
    final createdAt = row['created_at'];
    if (id is! String || senderId is! String || createdAt is! String) {
      return null;
    }
    final at = DateTime.tryParse(createdAt);
    final text = searchableTextOfRow(row, now);
    if (at == null || text == null) {
      return null;
    }
    final mentions = row['mentions'];
    return IndexedMessage(
      id: id,
      createdAtMs: at.millisecondsSinceEpoch,
      senderId: senderId,
      text: text,
      hasMask: hasMaskOfRow(row),
      pinned: row['is_pinned'] == true,
      mentionIds: [
        if (mentions is List)
          for (final mention in mentions)
            if (mention is Map &&
                mention['user_id'] is String &&
                (mention['user_id'] as String).isNotEmpty)
              mention['user_id'] as String,
      ],
    );
  }

  final String id;
  final int createdAtMs;
  final String senderId;

  /// What is found by: the message's words (and a file's name).
  final String text;

  /// The `has:` kinds, a bit each (see [hasBit]).
  final int hasMask;
  final bool pinned;
  final List<String> mentionIds;

  /// [text] folded for matching (see [foldSearchText]); made on first use.
  late final String folded = foldSearchText(text);

  List<dynamic> toJson() => [
    id,
    createdAtMs,
    senderId,
    hasMask,
    pinned ? 1 : 0,
    text,
    if (mentionIds.isNotEmpty) mentionIds,
  ];
}

/// A person who wrote messages of a conversation, for `from:` filters and
/// to name the author of a result.
class IndexedPerson {
  const IndexedPerson({required this.username, required this.displayName});

  final String username;
  final String displayName;
}

/// What the offline search knows about one conversation: its messages and
/// the people who wrote them.
class ConversationIndex {
  ConversationIndex({
    required this.messages,
    this.people = const {},
    this.encodedLength = 0,
  });

  factory ConversationIndex.decode(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return ConversationIndex(
      messages: [
        for (final item in json['d'] as List<dynamic>)
          IndexedMessage.fromJson(item as List<dynamic>),
      ],
      people: {
        for (final entry in (json['p'] as Map<String, dynamic>).entries)
          entry.key: IndexedPerson(
            username: (entry.value as List<dynamic>)[0] as String,
            displayName: (entry.value as List<dynamic>)[1] as String,
          ),
      },
      encodedLength: text.length,
    );
  }

  /// The index of the cached [rows] of a conversation.
  factory ConversationIndex.fromRows(
    Iterable<Map<String, dynamic>> rows,
    DateTime now,
  ) {
    final messages = <IndexedMessage>[];
    final people = <String, IndexedPerson>{};
    for (final row in rows) {
      final message = IndexedMessage.fromRow(row, now);
      if (message == null) {
        continue;
      }
      messages.add(message);
      final sender = row['sender'];
      if (sender is Map) {
        final username = sender['username'];
        final name = sender['display_name'];
        if (username is String) {
          people[message.senderId] = IndexedPerson(
            username: username,
            displayName: name is String ? name : username,
          );
        }
      }
    }
    return ConversationIndex(messages: messages, people: people);
  }

  final List<IndexedMessage> messages;
  final Map<String, IndexedPerson> people;

  /// How long the stored text was (characters), when it was read from
  /// storage or written to it.
  final int encodedLength;

  String encode() => jsonEncode({
    'v': 1,
    'p': {
      for (final entry in people.entries)
        entry.key: [entry.value.username, entry.value.displayName],
    },
    'd': [for (final message in messages) message.toJson()],
  });

  ConversationIndex without(Set<String> ids) {
    return ConversationIndex(
      messages: [
        for (final message in messages)
          if (!ids.contains(message.id)) message,
      ],
      people: people,
    );
  }
}

/// The offline search index: for each cached conversation the words of the
/// messages that can be found, kept in a store that encrypts them (see
/// `SealedKeyValueStore`) and, once a search needs them, in memory too.
///
/// Searching is a plain scan of those words: the cache holds at most 100
/// messages per conversation, so even a large cache is a few megabytes of
/// text, which a scan goes through in a few milliseconds, and a scan finds
/// Chinese by its characters without any word splitting.
///
/// The index follows the cache: whatever the cache forgets (a deleted,
/// expired, held back or one-time message, a cleared chat, a sign-out) is
/// forgotten here at the same moment (see `IndexedChatCache`).
class LocalSearchIndex {
  LocalSearchIndex(this.store);

  /// Where the index is kept; it should encrypt what it stores.
  final KeyValueStore store;

  static String _prefix(String userId) => 'u/$userId/s/';
  static String _key(String userId, String conversationId) =>
      '${_prefix(userId)}$conversationId';

  /// Per user, the conversations read so far (all of them once
  /// [load]'s future completes).
  final _memory = <String, Map<String, ConversationIndex>>{};
  final _loads = <String, Future<Map<String, ConversationIndex>>>{};
  final _versions = <String, int>{};

  int _bump(String userId, String conversationId) {
    final key = _key(userId, conversationId);
    return _versions[key] = (_versions[key] ?? 0) + 1;
  }

  int _version(String userId, String conversationId) =>
      _versions[_key(userId, conversationId)] ?? 0;

  /// Changes whenever [conversationId] is written, trimmed or forgotten.
  int versionOf(String userId, String conversationId) =>
      _version(userId, conversationId);

  /// [replace], unless the conversation changed since [version] was read
  /// (a newer write got there first).
  Future<void> replaceIfUnchanged(
    String userId,
    String conversationId,
    ConversationIndex index,
    int version,
  ) async {
    if (_version(userId, conversationId) == version) {
      await replace(userId, conversationId, index);
    }
  }

  /// Replaces what is known of a conversation.
  Future<void> replace(
    String userId,
    String conversationId,
    ConversationIndex index,
  ) async {
    _bump(userId, conversationId);
    final text = index.encode();
    final stored = ConversationIndex(
      messages: index.messages,
      people: index.people,
      encodedLength: text.length,
    );
    _memory[userId]?[conversationId] = stored;
    await store.write(_key(userId, conversationId), text);
  }

  /// Forgets messages (a recalled or expired one) of a conversation.
  Future<void> removeMessages(
    String userId,
    String conversationId,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) {
      return;
    }
    final current = await _read(userId, conversationId);
    if (current == null) {
      return;
    }
    final kept = current.without(ids);
    if (kept.messages.length == current.messages.length) {
      return;
    }
    await replace(userId, conversationId, kept);
  }

  /// Forgets a conversation altogether.
  Future<void> removeConversation(String userId, String conversationId) async {
    _bump(userId, conversationId);
    _memory[userId]?.remove(conversationId);
    await store.delete(_key(userId, conversationId));
  }

  /// Forgets everything of one user.
  Future<void> clearUser(String userId) async {
    final prefix = _prefix(userId);
    for (final key in _versions.keys.toList()) {
      if (key.startsWith(prefix)) {
        _versions[key] = (_versions[key] ?? 0) + 1;
      }
    }
    _memory.remove(userId);
    _loads.remove(userId);
    for (final key in await store.keys()) {
      if (key.startsWith(prefix)) {
        await store.delete(key);
      }
    }
  }

  /// Forgets everything, of every user.
  Future<void> clear() async {
    for (final key in _versions.keys.toList()) {
      _versions[key] = (_versions[key] ?? 0) + 1;
    }
    _memory.clear();
    _loads.clear();
    await store.clear();
  }

  /// The conversations that have an entry (even an empty one).
  Future<Set<String>> indexedConversations(String userId) async {
    final prefix = _prefix(userId);
    return {
      for (final key in await store.keys())
        if (key.startsWith(prefix)) key.substring(prefix.length),
    };
  }

  Future<ConversationIndex?> _read(String userId, String conversationId) async {
    final loaded = _memory[userId]?[conversationId];
    if (loaded != null) {
      return loaded;
    }
    final text = await store.read(_key(userId, conversationId));
    if (text == null) {
      return null;
    }
    try {
      return ConversationIndex.decode(text);
    } on Object {
      return null;
    }
  }

  /// Everything known of [userId], read from storage on the first call
  /// (one conversation at a time, with [pause] between, so the app keeps
  /// drawing).
  Future<Map<String, ConversationIndex>> load(
    String userId, {
    Future<void> Function()? pause,
  }) {
    final memory = _memory[userId];
    if (memory != null && !_loads.containsKey(userId)) {
      return Future.value(memory);
    }
    return _loads[userId] ??= _loadAll(userId, pause).whenComplete(() {
      _loads.remove(userId);
    });
  }

  Future<Map<String, ConversationIndex>> _loadAll(
    String userId,
    Future<void> Function()? pause,
  ) async {
    final map = _memory[userId] ??= {};
    final prefix = _prefix(userId);
    final List<String> keys;
    try {
      keys = await store.keys();
    } on Object {
      // Not read at all: the next search tries again.
      if (identical(_memory[userId], map)) {
        _memory.remove(userId);
      }
      rethrow;
    }
    for (final key in keys) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final conversationId = key.substring(prefix.length);
      if (map.containsKey(conversationId)) {
        continue;
      }
      final version = _version(userId, conversationId);
      try {
        final text = await store.read(key);
        if (text != null &&
            version == _version(userId, conversationId) &&
            !map.containsKey(conversationId) &&
            identical(_memory[userId], map)) {
          map[conversationId] = ConversationIndex.decode(text);
        }
      } on Object {
        // Damaged or from another key: this conversation is not searchable
        // until the cache is written again.
      }
      await pause?.call();
    }
    return map;
  }

  /// Bytes the stored index takes for each conversation of [userId], as
  /// characters of the stored text.
  Future<Map<String, int>> sizes(String userId) async {
    final map = await load(userId);
    return {
      for (final entry in map.entries) entry.key: entry.value.encodedLength,
    };
  }
}
