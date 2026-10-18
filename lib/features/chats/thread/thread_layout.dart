// Pure layout and read-state logic of the chat thread: how the loaded
// messages are sorted, grouped and divided for the list, where the NEW
// divider goes, which outgoing message shows "Read", and when slowmode ends.
// Nothing here touches widgets or providers, so it is unit-tested directly
// (test/features/chats/thread/thread_layout_test.dart).
import 'package:wecord/features/chats/media_send/album_fold.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

/// The other member of a direct conversation, from its read markers (one
/// per member).
String? directPeerIdFrom(
  List<ConversationReadMarker>? readMarkers,
  String? currentUserId,
) {
  for (final marker in readMarkers ?? const <ConversationReadMarker>[]) {
    if (marker.userId != currentUserId) {
      return marker.userId;
    }
  }
  return null;
}

/// Messages from the same sender this close together read as one group.
const messageGroupWindow = Duration(minutes: 7);

/// Ids of messages that continue the previous message's group: same sender,
/// at most [messageGroupWindow] apart, on the same day, and with no system
/// notice or NEW divider between them.
Set<String> followUpMessageIds(
  List<ChatMessage> oldestToNewest, {
  required String? newMessageDividerId,
}) {
  final ids = <String>{};
  for (var index = 1; index < oldestToNewest.length; index++) {
    final previous = oldestToNewest[index - 1];
    final message = oldestToNewest[index];
    if (message.type == MessageType.system ||
        previous.type == MessageType.system ||
        message.authorKey != previous.authorKey ||
        message.id == newMessageDividerId) {
      continue;
    }
    final gap = message.createdAt.difference(previous.createdAt);
    if (gap.isNegative || gap > messageGroupWindow) {
      continue;
    }
    if (!isSameLocalDay(previous.createdAt, message.createdAt)) {
      continue;
    }
    ids.add(message.id);
  }
  return ids;
}

bool isSameLocalDay(DateTime left, DateTime right) {
  final localLeft = left.toLocal();
  final localRight = right.toLocal();
  return localLeft.year == localRight.year &&
      localLeft.month == localRight.month &&
      localLeft.day == localRight.day;
}

/// When the current user's slowmode wait ends: their latest message plus
/// [slowmodeSeconds], or the server's [retryAt] if later. Null when they
/// have not sent anything here.
DateTime? slowmodeEnd({
  required List<ChatMessage> messages,
  required String? currentUserId,
  required int slowmodeSeconds,
  required DateTime? retryAt,
}) {
  DateTime? lastSentAt;
  for (final message in messages) {
    if (message.isSentBy(currentUserId) &&
        message.type != MessageType.system &&
        (lastSentAt == null || message.createdAt.isAfter(lastSentAt))) {
      lastSentAt = message.createdAt;
    }
  }
  final localEnd = lastSentAt?.add(Duration(seconds: slowmodeSeconds));
  if (retryAt == null) {
    return localEnd;
  }
  if (localEnd == null || retryAt.isAfter(localEnd)) {
    return retryAt;
  }
  return localEnd;
}

/// The newest message the current user sent, or null ([messages] are oldest
/// first).
ChatMessage? _latestOutgoing(List<ChatMessage> messages, String currentUserId) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.isSentBy(currentUserId) && message.type != MessageType.system) {
      return message;
    }
  }
  return null;
}

/// What a chat tells the sender about who read the newest message.
enum ReadReceiptScope {
  /// Nothing: the note to self, circle channels, threads, chats whose kind is
  /// not known yet.
  none,

  /// A direct chat: "Read" once the other person has read it.
  direct,

  /// A group: "N read" (the list is behind it).
  group;

  /// The scope of a chat of [type]; [noteToSelf] has none.
  static ReadReceiptScope of(
    ConversationType? type, {
    bool noteToSelf = false,
  }) {
    if (noteToSelf) {
      return none;
    }
    return switch (type) {
      ConversationType.direct => direct,
      ConversationType.group => group,
      _ => none,
    };
  }
}

/// The newest own message and who read it.
///
/// In a direct chat that is "Read" once the other person has read it. In a
/// group the same fact is a count ([LatestOutgoingReadState.groupReadCount]),
/// never "Read": one member out of many having read it would mislead. The
/// server leaves out of the markers the people who turned read receipts off
/// (and everyone, for a person who turned them off), so they count for
/// nothing.
LatestOutgoingReadState latestOutgoingReadStateOf({
  required List<ChatMessage> messages,
  required List<ConversationReadMarker> readMarkers,
  required String? currentUserId,
  required ReadReceiptScope scope,
}) {
  if (currentUserId == null || scope == ReadReceiptScope.none) {
    return const LatestOutgoingReadState();
  }
  final latestOutgoing = _latestOutgoing(messages, currentUserId);
  if (latestOutgoing == null) {
    return const LatestOutgoingReadState();
  }
  final messagesById = {for (final m in messages) m.id: m};
  final readers = readMarkers.where((marker) {
    if (marker.userId == currentUserId) {
      return false;
    }
    final readMessage = messagesById[marker.lastReadMessageId];
    return readMessage != null &&
        !readMessage.createdAt.isBefore(latestOutgoing.createdAt);
  }).length;
  return LatestOutgoingReadState(
    latestOutgoingMessageId: latestOutgoing.id,
    isRead: scope == ReadReceiptScope.direct && readers > 0,
    groupReadCount: scope == ReadReceiptScope.group ? readers : 0,
  );
}

/// The first message from someone else after the reader's last read message,
/// or null when everything was already read or the read position is unknown.
String? firstUnreadMessageId({
  required List<ChatMessage> messages,
  required List<ConversationReadMarker> readMarkers,
  required String? currentUserId,
}) {
  if (currentUserId == null) {
    return null;
  }
  ConversationReadMarker? marker;
  for (final readMarker in readMarkers) {
    if (readMarker.userId == currentUserId) {
      marker = readMarker;
      break;
    }
  }
  if (marker == null) {
    return null;
  }
  final lastReadMessageId = marker.lastReadMessageId;
  var startIndex = 0;
  if (lastReadMessageId != null) {
    final lastReadIndex = messages.indexWhere(
      (message) => message.id == lastReadMessageId,
    );
    if (lastReadIndex == -1) {
      return null;
    }
    startIndex = lastReadIndex + 1;
  }
  for (final message in messages.skip(startIndex)) {
    // A pat is a quiet line, never the first unread message.
    if (!message.isSentBy(currentUserId) && !isPatMessage(message)) {
      return message.id;
    }
  }
  return null;
}

List<ChatMessage> messagesOldestToNewest(List<ChatMessage> messages) {
  return [...messages]..sort((left, right) {
    final createdCompare = left.createdAt.compareTo(right.createdAt);
    if (createdCompare != 0) {
      return createdCompare;
    }
    return left.id.compareTo(right.id);
  });
}

class LatestOutgoingReadState {
  const LatestOutgoingReadState({
    this.latestOutgoingMessageId,
    this.isRead = false,
    this.groupReadCount = 0,
  });

  final String? latestOutgoingMessageId;

  /// A direct chat: the other person has read it.
  final bool isRead;

  /// A group: how many members have read it.
  final int groupReadCount;
}

/// The loaded messages laid out for the list (see
/// `_ChatThreadScreenState._layoutFor`).

class ThreadLayout {
  ThreadLayout._({
    required this.messages,
    required this.readMarkers,
    required this.pending,
    required this.query,
    required this.dividerId,
    required this.currentUserId,
    required this.fullOldestToNewest,
    required this.messagesById,
    required this.display,
    required this.displayIndex,
    required this.pendingById,
    required this.followUpIds,
    required this.dayStartIds,
    required this.openingPostId,
    required this.openingPostReplyCount,
    required this.latestOutgoingReadState,
    required this.readScope,
  });

  factory ThreadLayout.build({
    required List<ChatMessage> messages,
    required List<ConversationReadMarker> readMarkers,
    required List<OutboxEntry> pending,
    required String query,
    required String? dividerId,
    required String? currentUserId,
    required bool forumPost,
    required ReadReceiptScope readScope,
    required List<ChatMessage> Function(List<ChatMessage>, String) search,
  }) {
    final searching = query.trim().isNotEmpty;
    final fullOldestToNewest = isOldestFirst(messages)
        ? messages
        : messagesOldestToNewest(messages);
    final messagesById = {
      for (final message in fullOldestToNewest) message.id: message,
    };
    final visible = searching
        ? messagesOldestToNewest(search(fullOldestToNewest, query))
        : fullOldestToNewest;
    // Messages still in the outbox follow the loaded ones, unless the
    // stored copy already arrived.
    final storedClientIds = {
      for (final message in fullOldestToNewest) ?message.clientId,
    };
    final pendingById = <String, OutboxEntry>{};
    final pendingMessages = <ChatMessage>[];
    if (!searching && currentUserId != null) {
      for (final entry in pending) {
        if (storedClientIds.contains(entry.clientId)) {
          continue;
        }
        pendingById[entry.pendingMessageId] = entry;
        pendingMessages.add(entry.toPendingMessage(currentUserId));
      }
    }
    final unfolded = pendingMessages.isEmpty
        ? visible
        : [...visible, ...pendingMessages];
    // Pictures sent together show as one album bubble. (Not while
    // searching: a result is a single message.)
    final folded = searching
        ? FoldedAlbums(messages: unfolded, headOf: const {})
        : foldAlbums(unfolded);
    final display = folded.messages;
    final displayIndex = {
      for (final (index, message) in display.indexed) message.id: index,
    };
    // The rest of an album is found where its first message is.
    for (final MapEntry(key: siblingId, value: headId)
        in folded.headOf.entries) {
      displayIndex[siblingId] = displayIndex[headId]!;
    }
    // Grouping compares neighbours, which search results are not.
    final followUpIds = !searching
        ? followUpMessageIds(display, newMessageDividerId: dividerId)
        : <String>{};
    // The first message of each day gets a day separator.
    final dayStartIds = <String>{
      if (!searching)
        for (final (index, message) in display.indexed)
          if (index == 0 ||
              !isSameLocalDay(display[index - 1].createdAt, message.createdAt))
            message.id,
    };
    // A forum post opens with its first message; replies start their own
    // group under it.
    final openingPostId = forumPost
        ? fullOldestToNewest
              .where((message) => message.type != MessageType.system)
              .firstOrNull
              ?.id
        : null;
    var openingPostReplyCount = 0;
    if (openingPostId != null) {
      final index = displayIndex[openingPostId];
      if (index != null && index + 1 < display.length) {
        followUpIds.remove(display[index + 1].id);
      }
      openingPostReplyCount = fullOldestToNewest
          .where(
            (other) =>
                other.id != openingPostId &&
                other.type != MessageType.system &&
                other.recalledAt == null,
          )
          .length;
    }
    return ThreadLayout._(
      messages: messages,
      readMarkers: readMarkers,
      pending: pending,
      query: query,
      dividerId: dividerId,
      currentUserId: currentUserId,
      fullOldestToNewest: fullOldestToNewest,
      messagesById: messagesById,
      display: display,
      displayIndex: displayIndex,
      pendingById: pendingById,
      followUpIds: followUpIds,
      dayStartIds: dayStartIds,
      openingPostId: openingPostId,
      openingPostReplyCount: openingPostReplyCount,
      latestOutgoingReadState: latestOutgoingReadStateOf(
        messages: fullOldestToNewest,
        readMarkers: readMarkers,
        currentUserId: currentUserId,
        scope: readScope,
      ),
      readScope: readScope,
    );
  }

  // What it was built from.
  final List<ChatMessage> messages;
  final List<ConversationReadMarker> readMarkers;

  /// What the chat tells about who read the newest own message.
  final ReadReceiptScope readScope;
  final List<OutboxEntry> pending;
  final String query;
  final String? dividerId;
  final String? currentUserId;

  /// Every loaded message, oldest first.
  final List<ChatMessage> fullOldestToNewest;
  final Map<String, ChatMessage> messagesById;

  /// What the list shows, oldest first: the search results, or the loaded
  /// messages and then the ones still sending.
  final List<ChatMessage> display;
  final Map<String, int> displayIndex;

  /// Outbox entries by the id their message shows under.
  final Map<String, OutboxEntry> pendingById;

  /// The outbox entry that [message]'s bubble shows the status of: its own,
  /// or for an album the first of its attachments that failed, else the
  /// first still sending.
  OutboxEntry? pendingEntryFor(ChatMessage message) {
    final album = message.album;
    if (album == null) {
      return pendingById[message.id];
    }
    OutboxEntry? sending;
    for (final item in album) {
      final entry = pendingById[item.id];
      if (entry == null) {
        continue;
      }
      if (entry.state == OutboxState.failed) {
        return entry;
      }
      sending ??= entry;
    }
    return sending;
  }

  final Set<String> followUpIds;
  final Set<String> dayStartIds;
  final String? openingPostId;
  final int openingPostReplyCount;
  final LatestOutgoingReadState latestOutgoingReadState;
}

bool isOldestFirst(List<ChatMessage> messages) {
  for (var index = 1; index < messages.length; index++) {
    final previous = messages[index - 1];
    final message = messages[index];
    final byTime = previous.createdAt.compareTo(message.createdAt);
    if (byTime > 0 || (byTime == 0 && previous.id.compareTo(message.id) > 0)) {
      return false;
    }
  }
  return true;
}

/// Whether [id] is [message] or, for an album, its last message.
bool messageEndsAt(ChatMessage message, String? id) {
  if (id == null) {
    return false;
  }
  return message.id == id || message.album?.last.id == id;
}
