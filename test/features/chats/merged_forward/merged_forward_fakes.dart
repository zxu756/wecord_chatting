import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/contact_cards/contact_cards_repository.dart';
import 'package:wecord/shared/models/message.dart';

/// Records merged forwards and serves bundles by message id.
class FakeMergedForwardRepository implements MergedForwardRepository {
  FakeMergedForwardRepository({Map<String, ChatHistoryBundle>? bundles})
    : bundles = bundles ?? {};

  final Map<String, ChatHistoryBundle> bundles;
  final forwards = <({List<String> ids, String target, String title})>[];
  Object? failWith;
  var _next = 0;

  @override
  Future<String> forwardMerged({
    required List<String> sourceMessageIds,
    required String targetConversationId,
    required String title,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    forwards.add((
      ids: sourceMessageIds,
      target: targetConversationId,
      title: title,
    ));
    return 'bundle-${_next++}';
  }

  @override
  Future<ChatHistoryBundle> loadBundle(String messageId) async {
    final bundle = bundles[messageId];
    if (bundle == null) {
      throw const MergedForwardException(MergedForwardRefusal.other);
    }
    return bundle;
  }
}

/// Records contact cards.
class FakeContactCardsRepository implements ContactCardsRepository {
  final sent =
      <({String conversationId, ContactCardKind kind, String targetId})>[];
  Object? failWith;

  @override
  Future<String> send({
    required String conversationId,
    required ContactCardKind kind,
    required String targetId,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    sent.add((conversationId: conversationId, kind: kind, targetId: targetId));
    return 'card-${sent.length}';
  }
}

/// A chat-history message as the server stores it.
ChatMessage chatHistoryMessage({
  String id = 'history-1',
  String title = 'Climbing crew',
  int count = 5,
  String senderId = 'user-2',
  DateTime? createdAt,
  List<Map<String, dynamic>>? preview,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: 'Chat history: $title',
    createdAt: createdAt ?? DateTime.utc(2026, 5, 18, 4, 40),
    attachment: {
      'kind': 'chat_history',
      'title': title,
      'count': count,
      'preview':
          preview ??
          [
            {'name': 'Ada', 'kind': 'text', 'text': 'Meet at 7?'},
            {'name': 'Bart', 'kind': 'text', 'text': 'Works for me'},
            {'name': 'Ada', 'kind': 'image', 'text': ''},
            {'name': 'Bart', 'kind': 'file', 'text': 'plan.pdf'},
          ],
    },
  );
}

/// A contact card message.
ChatMessage contactCardMessage({
  String id = 'card-1',
  Map<String, dynamic>? card,
  String senderId = 'user-2',
  DateTime? createdAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: MessageType.text,
    body: 'Contact card: Grace Hopper',
    createdAt: createdAt ?? DateTime.utc(2026, 5, 18, 4, 41),
    attachment:
        card ??
        {
          'kind': 'contact_card',
          'card': 'user',
          'user_id': 'user-9',
          'name': 'Grace Hopper',
          'username': 'grace',
        },
  );
}

/// Items for a chat history of text lines by Ada and Bart.
List<Map<String, dynamic>> bundleItemJson() => [
  {
    'message_id': 'src-1',
    'sender_id': 'user-2',
    'sender_name': 'Ada',
    'created_at': '2026-05-17T18:30:00+00:00',
    'type': 'text',
    'body': 'Meet at 7?',
  },
  {
    'message_id': 'src-2',
    'sender_id': 'user-3',
    'sender_name': 'Bart',
    'created_at': '2026-05-17T18:31:00+00:00',
    'type': 'text',
    'body': 'Works for me',
  },
  {
    'message_id': 'src-3',
    'sender_id': 'user-2',
    'sender_name': 'Ada',
    'created_at': '2026-05-18T08:00:00+00:00',
    'type': 'image',
    'body': '',
    'attachment': {
      'kind': 'image',
      'bucket': 'chat-images',
      'path': 'src/pic.png',
      'mime_type': 'image/png',
      'size': 1200,
      'width': 400,
      'height': 300,
    },
  },
  {
    'message_id': 'src-4',
    'sender_id': 'user-3',
    'sender_name': 'Bart',
    'created_at': '2026-05-18T08:02:00+00:00',
    'type': 'file',
    'body': '',
    'attachment': {
      'kind': 'file',
      'bucket': 'chat-files',
      'path': 'src/plan.pdf',
      'name': 'plan.pdf',
      'mime_type': 'application/pdf',
      'size': 20480,
    },
  },
];
