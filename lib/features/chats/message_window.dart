import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/message.dart';

/// The loaded part of a conversation's history: a run of consecutive
/// messages, oldest first, and whether the server has more before or after
/// it. Changes return a new window; the lists are never changed in place.
class MessageWindow {
  MessageWindow({
    required List<ChatMessage> messages,
    this.hasOlder = false,
    this.hasNewer = false,
  }) : messages = List.unmodifiable(messages);

  static final empty = MessageWindow(messages: const []);

  /// The newest page of a conversation; [limit] is what was asked for, so
  /// a full page means there may be older messages.
  factory MessageWindow.latest(
    List<ChatMessage> page, {
    int limit = messagePageSize,
  }) {
    return MessageWindow(
      messages: _sortedUnique(page),
      hasOlder: page.length >= limit,
    );
  }

  /// The oldest page of a conversation (forum posts read from the start).
  factory MessageWindow.earliest(
    List<ChatMessage> page, {
    int limit = messagePageSize,
  }) {
    return MessageWindow(
      messages: _sortedUnique(page),
      hasNewer: page.length >= limit,
    );
  }

  /// The pages around [target]: [before] (older, up to [limit]) and
  /// [after] (newer, up to [limit]).
  factory MessageWindow.around(
    ChatMessage target, {
    required List<ChatMessage> before,
    required List<ChatMessage> after,
    required int limit,
  }) {
    return MessageWindow(
      messages: _sortedUnique([...before, target, ...after]),
      hasOlder: before.length >= limit,
      hasNewer: after.length >= limit,
    );
  }

  /// Oldest first, each id once.
  final List<ChatMessage> messages;

  /// The server has messages older than the oldest one here.
  final bool hasOlder;

  /// The server has messages newer than the newest one here: the reader
  /// jumped back in history.
  final bool hasNewer;

  /// Whether the window reaches the conversation's newest message, so new
  /// messages belong in it.
  bool get isLive => !hasNewer;

  bool get isEmpty => messages.isEmpty;

  MessageCursor? get oldest =>
      messages.isEmpty ? null : MessageCursor.of(messages.first);

  MessageCursor? get newest =>
      messages.isEmpty ? null : MessageCursor.of(messages.last);

  late final Map<String, int> _indexById = {
    for (final (index, message) in messages.indexed) message.id: index,
  };

  bool contains(String messageId) => _indexById.containsKey(messageId);

  ChatMessage? byId(String messageId) {
    final index = _indexById[messageId];
    return index == null ? null : messages[index];
  }

  /// The message the sender's app sent with [clientId], if loaded.
  ChatMessage? byClientId(String clientId) {
    for (final message in messages.reversed) {
      if (message.clientId == clientId) {
        return message;
      }
    }
    return null;
  }

  MessageWindow copyWith({
    List<ChatMessage>? messages,
    bool? hasOlder,
    bool? hasNewer,
  }) {
    return MessageWindow(
      messages: messages ?? this.messages,
      hasOlder: hasOlder ?? this.hasOlder,
      hasNewer: hasNewer ?? this.hasNewer,
    );
  }

  /// Adds a page loaded before the oldest message. A page shorter than
  /// [limit] reached the start of the conversation.
  MessageWindow withOlder(
    List<ChatMessage> page, {
    int limit = messagePageSize,
  }) {
    return MessageWindow(
      messages: _merge(messages, page),
      hasOlder: page.length >= limit,
      hasNewer: hasNewer,
    );
  }

  /// Adds a page loaded after the newest message. A page shorter than
  /// [limit] reached the newest message.
  MessageWindow withNewer(
    List<ChatMessage> page, {
    int limit = messagePageSize,
  }) {
    return MessageWindow(
      messages: _merge(messages, page),
      hasOlder: hasOlder,
      hasNewer: page.length >= limit,
    );
  }

  /// Puts new or changed messages (from realtime) in place. A message
  /// replaces the loaded one with its id; a new one joins when it falls
  /// inside the window, after it while the window is live, or before it
  /// when the window starts at the conversation's beginning. Messages
  /// outside the window stay out, so it remains one unbroken run.
  MessageWindow upsert(Iterable<ChatMessage> changed) {
    final oldest = this.oldest;
    final newest = this.newest;
    final replaced = <String, ChatMessage>{};
    final added = <ChatMessage>[];
    for (final message in changed) {
      if (contains(message.id)) {
        replaced[message.id] = message;
        continue;
      }
      final cursor = MessageCursor.of(message);
      final fits =
          oldest == null ||
          newest == null ||
          ((!cursor.isBefore(oldest) || !hasOlder) &&
              (!cursor.isAfter(newest) || isLive));
      if (fits) {
        added.add(message);
      }
    }
    if (replaced.isEmpty && added.isEmpty) {
      return this;
    }
    var next = [
      for (final message in messages) replaced[message.id] ?? message,
    ];
    if (added.isNotEmpty) {
      // New messages usually arrive at the end, already in order.
      added.sort(compareMessages);
      final appendOnly =
          newest == null || MessageCursor.of(added.first).isAfter(newest);
      next = appendOnly ? [...next, ...added] : _merge(next, added);
    }
    return MessageWindow(
      messages: next,
      hasOlder: hasOlder,
      hasNewer: hasNewer,
    );
  }

  /// Drops [messageIds] (deleted on the server).
  MessageWindow remove(Iterable<String> messageIds) {
    final ids = messageIds.where(contains).toSet();
    if (ids.isEmpty) {
      return this;
    }
    return MessageWindow(
      messages: [
        for (final message in messages)
          if (!ids.contains(message.id)) message,
      ],
      hasOlder: hasOlder,
      hasNewer: hasNewer,
    );
  }

  /// Takes a freshly loaded run of consecutive messages ([page], oldest
  /// first) as the truth for the span it covers: loaded messages in that
  /// span that the page lacks were deleted, the others are replaced.
  /// [reachesStart] / [reachesEnd] say the page covers everything before
  /// its first / after its last message (a short page).
  MessageWindow replaceSpan(
    List<ChatMessage> page, {
    bool reachesStart = false,
    bool reachesEnd = false,
  }) {
    if (page.isEmpty) {
      if (reachesStart && reachesEnd) {
        return MessageWindow(messages: const []);
      }
      return this;
    }
    final sortedPage = _sortedUnique(page);
    final first = MessageCursor.of(sortedPage.first);
    final last = MessageCursor.of(sortedPage.last);
    bool inSpan(ChatMessage message) {
      final cursor = MessageCursor.of(message);
      return (reachesStart || !cursor.isBefore(first)) &&
          (reachesEnd || !cursor.isAfter(last));
    }

    final kept = [
      for (final message in messages)
        if (!inSpan(message)) message,
    ];
    return MessageWindow(
      messages: _merge(kept, sortedPage),
      hasOlder: reachesStart ? false : hasOlder,
      hasNewer: reachesEnd ? false : hasNewer,
    );
  }

  /// Brings a window (for example one read from the offline cache) up to
  /// date with the conversation's newest page, [latest] (asked with
  /// [limit]). When the page and the window overlap or touch, the window
  /// keeps its older messages and takes the page for the rest; when there
  /// is a gap between them (more new messages than a page), the window
  /// starts over from the page.
  MessageWindow syncWithLatest(
    List<ChatMessage> latest, {
    int limit = messagePageSize,
  }) {
    final pageIsFull = latest.length >= limit;
    if (latest.isEmpty) {
      return MessageWindow(messages: const []);
    }
    final fresh = MessageWindow.latest(latest, limit: limit);
    if (!pageIsFull || messages.isEmpty) {
      return fresh;
    }
    final newest = this.newest!;
    final pageStart = fresh.oldest!;
    if (newest.isBefore(pageStart)) {
      // Nothing in common: the messages in between are unknown.
      return fresh;
    }
    final synced = replaceSpan(fresh.messages, reachesEnd: true);
    final keepsOlder =
        synced.messages.isNotEmpty &&
        MessageCursor.of(synced.messages.first).isBefore(pageStart);
    return synced.copyWith(hasOlder: keepsOlder ? hasOlder : true);
  }

  /// The newest [count] messages, for the offline cache.
  List<ChatMessage> newestMessages(int count) {
    return messages.length <= count
        ? messages
        : messages.sublist(messages.length - count);
  }

  @override
  String toString() {
    return 'MessageWindow(${messages.length} messages, '
        'hasOlder: $hasOlder, hasNewer: $hasNewer)';
  }
}

List<ChatMessage> _sortedUnique(Iterable<ChatMessage> messages) {
  final byId = <String, ChatMessage>{
    for (final message in messages) message.id: message,
  };
  return byId.values.toList()..sort(compareMessages);
}

/// Both lists oldest first; [incoming] wins for shared ids.
List<ChatMessage> _merge(
  List<ChatMessage> existing,
  List<ChatMessage> incoming,
) {
  if (incoming.isEmpty) {
    return existing;
  }
  if (existing.isEmpty) {
    return _sortedUnique(incoming);
  }
  return _sortedUnique([...existing, ...incoming]);
}
