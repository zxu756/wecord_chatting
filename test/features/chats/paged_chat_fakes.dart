import 'dart:async';

import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/message.dart';

import 'chat_thread_screen_test.dart' as thread_test;

/// A message row as the server sends it.
Map<String, dynamic> messageRow(
  int index, {
  String? id,
  String senderId = 'user-2',
  String? body,
  String type = 'text',
  Map<String, dynamic>? attachment,
  DateTime? createdAt,
  String? clientId,
}) {
  return {
    'id': id ?? 'message-${index.toString().padLeft(4, '0')}',
    'conversation_id': 'conversation-1',
    'sender_id': senderId,
    'type': type,
    'body': body ?? 'Message $index',
    'attachment': attachment,
    'created_at':
        (createdAt ??
                DateTime.utc(2026, 1, 1, 8).add(Duration(minutes: index * 3)))
            .toIso8601String(),
    'reactions': const <Object?>[],
    'client_id': clientId,
  };
}

/// [thread_test.FakeChatsRepository] with paged history and outbox sends:
/// [rows] is the server's conversation.
class PagedChatsRepository extends thread_test.FakeChatsRepository
    implements MessageHistorySource, OutboxMessageSender {
  var rows = <Map<String, dynamic>>[];

  /// Fetches fail as if offline.
  var offline = false;

  /// Answers wait for this when set.
  Completer<void>? gate;
  final pageRequests = <({MessageCursor? before, MessageCursor? after})>[];
  final byIdRequests = <List<String>>[];
  final queuedSends = <({String clientId, String body})>[];
  Object? queuedSendError;
  final _events = StreamController<ThreadEvent>.broadcast();

  void emit(ThreadEvent event) => _events.add(event);

  List<Map<String, dynamic>> get _sorted {
    final sorted = [...rows];
    sorted.sort((left, right) {
      final byTime = (left['created_at'] as String).compareTo(
        right['created_at'] as String,
      );
      return byTime != 0
          ? byTime
          : (left['id'] as String).compareTo(right['id'] as String);
    });
    return sorted;
  }

  MessageCursor _cursorOf(Map<String, dynamic> row) {
    return MessageCursor(
      DateTime.parse(row['created_at'] as String),
      row['id'] as String,
    );
  }

  Future<void> _answer() async {
    if (gate case final gate?) {
      await gate.future;
    }
    if (offline) {
      throw StateError('offline');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMessageRows(
    String conversationId, {
    MessageCursor? before,
    MessageCursor? after,
    int limit = messagePageSize,
  }) async {
    pageRequests.add((before: before, after: after));
    await _answer();
    final sorted = _sorted;
    if (after != null) {
      return sorted
          .where((row) => _cursorOf(row).isAfter(after))
          .take(limit)
          .toList();
    }
    final older = before == null
        ? sorted
        : sorted.where((row) => _cursorOf(row).isBefore(before)).toList();
    return older.length <= limit ? older : older.sublist(older.length - limit);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMessageRowsByIds(
    String conversationId,
    List<String> messageIds,
  ) async {
    byIdRequests.add(messageIds);
    await _answer();
    return [
      for (final row in _sorted)
        if (messageIds.contains(row['id'])) row,
    ];
  }

  @override
  Future<Map<String, List<dynamic>>> fetchReactions(
    String conversationId,
    List<String> messageIds,
  ) async {
    await _answer();
    return {
      for (final row in rows)
        if (messageIds.contains(row['id']) &&
            (row['reactions'] as List).isNotEmpty)
          row['id'] as String: row['reactions'] as List,
    };
  }

  @override
  ChatMessage messageFromRow(Map<String, dynamic> row) =>
      chatMessageFromRow(row);

  @override
  Stream<ThreadEvent> threadEvents(String conversationId) => _events.stream;

  @override
  Future<String?> sendQueuedTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {
    queuedSends.add((clientId: clientId, body: body));
    await _answer();
    if (queuedSendError case final error?) {
      throw error;
    }
    final existing = rows.where((row) => row['client_id'] == clientId);
    if (existing.isNotEmpty) {
      return existing.first['id'] as String;
    }
    final row = messageRow(
      rows.length + 10000,
      id: 'sent-${rows.length}',
      senderId: 'user-1',
      body: body,
      createdAt: DateTime.utc(2027),
      clientId: clientId,
    );
    rows = [...rows, row];
    return row['id'] as String;
  }
}
