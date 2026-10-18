import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/thread/thread_layout.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/message.dart';

ChatMessage message(
  String id, {
  String sender = 'other',
  required DateTime at,
  MessageType type = MessageType.text,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: sender,
    type: type,
    body: id,
    createdAt: at,
    recalledAt: recalledAt,
  );
}

void main() {
  final day = DateTime.utc(2026, 10, 18, 12);
  DateTime at(int minutes) => day.add(Duration(minutes: minutes));

  group('latestOutgoingReadStateOf', () {
    test('nothing without a signed-in user or an outgoing message', () {
      final messages = [message('a', at: at(0))];
      expect(
        latestOutgoingReadStateOf(
          messages: messages,
          readMarkers: const [],
          currentUserId: null,
        ).latestOutgoingMessageId,
        isNull,
      );
      expect(
        latestOutgoingReadStateOf(
          messages: messages,
          readMarkers: const [],
          currentUserId: 'me',
        ).latestOutgoingMessageId,
        isNull,
      );
    });

    test('the newest own message is read once someone else read past it', () {
      final messages = [
        message('a', sender: 'me', at: at(0)),
        message('b', sender: 'me', at: at(1)),
        message('c', at: at(2)),
      ];
      final unread = latestOutgoingReadStateOf(
        messages: messages,
        readMarkers: const [
          ConversationReadMarker(userId: 'other', lastReadMessageId: 'a'),
        ],
        currentUserId: 'me',
      );
      expect(unread.latestOutgoingMessageId, 'b');
      expect(unread.isRead, isFalse);

      final read = latestOutgoingReadStateOf(
        messages: messages,
        readMarkers: const [
          ConversationReadMarker(userId: 'other', lastReadMessageId: 'c'),
          ConversationReadMarker(userId: 'me', lastReadMessageId: 'a'),
        ],
        currentUserId: 'me',
      );
      expect(read.isRead, isTrue);
    });

    test('the current user\'s own marker does not count', () {
      final read = latestOutgoingReadStateOf(
        messages: [message('a', sender: 'me', at: at(0))],
        readMarkers: const [
          ConversationReadMarker(userId: 'me', lastReadMessageId: 'a'),
        ],
        currentUserId: 'me',
      );
      expect(read.isRead, isFalse);
    });
  });

  group('firstUnreadMessageId', () {
    final messages = [
      message('a', at: at(0)),
      message('b', sender: 'me', at: at(1)),
      message('c', at: at(2)),
      message('d', at: at(3)),
    ];

    test('is the first message from someone else after the read position', () {
      expect(
        firstUnreadMessageId(
          messages: messages,
          readMarkers: const [
            ConversationReadMarker(userId: 'me', lastReadMessageId: 'a'),
          ],
          currentUserId: 'me',
        ),
        'c',
      );
    });

    test('is null when everything was read or the position is unknown', () {
      expect(
        firstUnreadMessageId(
          messages: messages,
          readMarkers: const [
            ConversationReadMarker(userId: 'me', lastReadMessageId: 'd'),
          ],
          currentUserId: 'me',
        ),
        isNull,
      );
      expect(
        firstUnreadMessageId(
          messages: messages,
          readMarkers: const [
            ConversationReadMarker(userId: 'me', lastReadMessageId: 'gone'),
          ],
          currentUserId: 'me',
        ),
        isNull,
      );
      expect(
        firstUnreadMessageId(
          messages: messages,
          readMarkers: const [],
          currentUserId: 'me',
        ),
        isNull,
      );
    });

    test('a reader who never read anything starts at the first message', () {
      expect(
        firstUnreadMessageId(
          messages: messages,
          readMarkers: const [
            ConversationReadMarker(userId: 'me', lastReadMessageId: null),
          ],
          currentUserId: 'me',
        ),
        'a',
      );
    });
  });

  group('followUpMessageIds', () {
    test('groups same-sender messages within the window', () {
      final messages = [
        message('a', at: at(0)),
        message('b', at: at(3)),
        message('c', at: at(20)),
        message('d', sender: 'third', at: at(21)),
      ];
      expect(followUpMessageIds(messages, newMessageDividerId: null), {'b'});
    });

    test('breaks at the NEW divider and at system notices', () {
      final messages = [
        message('a', at: at(0)),
        message('b', at: at(1)),
        message('s', at: at(2), type: MessageType.system),
        message('c', at: at(3)),
      ];
      expect(followUpMessageIds(messages, newMessageDividerId: 'b'), isEmpty);
    });
  });

  group('ordering', () {
    test('messagesOldestToNewest sorts by time then id', () {
      final sorted = messagesOldestToNewest([
        message('b', at: at(1)),
        message('z', at: at(0)),
        message('a', at: at(1)),
      ]);
      expect([for (final m in sorted) m.id], ['z', 'a', 'b']);
    });

    test('isOldestFirst', () {
      expect(isOldestFirst(const []), isTrue);
      expect(
        isOldestFirst([message('a', at: at(0)), message('b', at: at(1))]),
        isTrue,
      );
      expect(
        isOldestFirst([message('a', at: at(1)), message('b', at: at(0))]),
        isFalse,
      );
    });
  });

  group('slowmodeEnd', () {
    test('is the latest own message plus the wait, or the server\'s later '
        'answer', () {
      final messages = [
        message('a', sender: 'me', at: at(0)),
        message('b', at: at(5)),
      ];
      expect(
        slowmodeEnd(
          messages: messages,
          currentUserId: 'me',
          slowmodeSeconds: 60,
          retryAt: null,
        ),
        at(1),
      );
      expect(
        slowmodeEnd(
          messages: messages,
          currentUserId: 'me',
          slowmodeSeconds: 60,
          retryAt: at(3),
        ),
        at(3),
      );
      expect(
        slowmodeEnd(
          messages: const [],
          currentUserId: 'me',
          slowmodeSeconds: 60,
          retryAt: null,
        ),
        isNull,
      );
    });
  });

  group('ThreadLayout', () {
    test('lays out days, the opening post and search results', () {
      final messages = [
        message('b', at: DateTime.utc(2026, 10, 19, 12)),
        message('a', at: DateTime.utc(2026, 10, 17, 12)),
      ];
      final layout = ThreadLayout.build(
        messages: messages,
        readMarkers: const [],
        pending: const [],
        query: '',
        dividerId: null,
        currentUserId: 'me',
        forumPost: true,
        search: (messages, query) => messages,
      );
      expect([for (final m in layout.display) m.id], ['a', 'b']);
      expect(layout.openingPostId, 'a');
      expect(layout.openingPostReplyCount, 1);
      expect(layout.displayIndex['b'], 1);

      final searched = ThreadLayout.build(
        messages: messages,
        readMarkers: const [],
        pending: const [],
        query: 'b',
        dividerId: null,
        currentUserId: 'me',
        forumPost: false,
        search: (messages, query) => [
          for (final m in messages)
            if (m.body == query) m,
        ],
      );
      expect([for (final m in searched.display) m.id], ['b']);
      expect(searched.followUpIds, isEmpty);
      expect(searched.dayStartIds, isEmpty);
    });
  });
}
