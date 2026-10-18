import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/thread/thread_layout.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
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
          scope: ReadReceiptScope.direct,
        ).latestOutgoingMessageId,
        isNull,
      );
      expect(
        latestOutgoingReadStateOf(
          messages: messages,
          readMarkers: const [],
          currentUserId: 'me',
          scope: ReadReceiptScope.direct,
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
        scope: ReadReceiptScope.direct,
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
        scope: ReadReceiptScope.direct,
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
        scope: ReadReceiptScope.direct,
      );
      expect(read.isRead, isFalse);
    });

    test('a group never says "Read": it counts the readers instead', () {
      final messages = [
        message('a', sender: 'me', at: at(0)),
        message('b', at: at(1)),
      ];
      final state = latestOutgoingReadStateOf(
        messages: messages,
        readMarkers: const [
          ConversationReadMarker(userId: 'one', lastReadMessageId: 'b'),
          ConversationReadMarker(userId: 'two', lastReadMessageId: null),
        ],
        currentUserId: 'me',
        scope: ReadReceiptScope.group,
      );
      expect(state.latestOutgoingMessageId, 'a');
      expect(state.isRead, isFalse);
      expect(state.groupReadCount, 1);
    });

    test('a direct chat has no group count', () {
      final state = latestOutgoingReadStateOf(
        messages: [
          message('a', sender: 'me', at: at(0)),
          message('b', at: at(1)),
        ],
        readMarkers: const [
          ConversationReadMarker(userId: 'one', lastReadMessageId: 'b'),
        ],
        currentUserId: 'me',
        scope: ReadReceiptScope.direct,
      );
      expect(state.isRead, isTrue);
      expect(state.groupReadCount, 0);
    });

    test('a chat with no scope tells nothing', () {
      final state = latestOutgoingReadStateOf(
        messages: [
          message('a', sender: 'me', at: at(0)),
          message('b', at: at(1)),
        ],
        readMarkers: const [
          ConversationReadMarker(userId: 'one', lastReadMessageId: 'b'),
        ],
        currentUserId: 'me',
        scope: ReadReceiptScope.none,
      );
      expect(state.latestOutgoingMessageId, isNull);
      expect(state.isRead, isFalse);
      expect(state.groupReadCount, 0);
    });
  });

  group('ReadReceiptScope.of', () {
    test('direct chats say "Read", groups count, the rest tell nothing', () {
      expect(
        ReadReceiptScope.of(ConversationType.direct),
        ReadReceiptScope.direct,
      );
      expect(
        ReadReceiptScope.of(ConversationType.group),
        ReadReceiptScope.group,
      );
      expect(
        ReadReceiptScope.of(ConversationType.channel),
        ReadReceiptScope.none,
      );
      expect(
        ReadReceiptScope.of(ConversationType.thread),
        ReadReceiptScope.none,
      );
      expect(ReadReceiptScope.of(null), ReadReceiptScope.none);
    });

    test('the note to self has none, though it is a direct chat', () {
      expect(
        ReadReceiptScope.of(ConversationType.direct, noteToSelf: true),
        ReadReceiptScope.none,
      );
    });
  });

  group('group read counts', () {
    final messages = [
      message('a', sender: 'me', at: at(0)),
      message('b', at: at(1)),
      message('c', sender: 'me', at: at(2)),
      message('d', at: at(3)),
    ];
    // Ann read to c, Bo to d, Cy only to b, Di to nothing; Zed's marker is
    // empty (receipts off: the server sends it without a position).
    const markers = [
      ConversationReadMarker(userId: 'me', lastReadMessageId: 'd'),
      ConversationReadMarker(userId: 'ann', lastReadMessageId: 'c'),
      ConversationReadMarker(userId: 'bo', lastReadMessageId: 'd'),
      ConversationReadMarker(userId: 'cy', lastReadMessageId: 'b'),
      ConversationReadMarker(userId: 'di', lastReadMessageId: null),
      ConversationReadMarker(userId: 'zed', lastReadMessageId: null),
    ];

    LatestOutgoingReadState state(
      List<ChatMessage> messages,
      List<ConversationReadMarker> markers,
    ) => latestOutgoingReadStateOf(
      messages: messages,
      readMarkers: markers,
      currentUserId: 'me',
      scope: ReadReceiptScope.group,
    );

    test('counts the others whose position is at or past the newest own', () {
      final result = state(messages, markers);
      expect(result.latestOutgoingMessageId, 'c');
      // Ann (exactly at c) and Bo (past it); my own marker, Cy, Di and Zed
      // do not count.
      expect(result.groupReadCount, 2);
    });

    test('is 0 when nobody has read it', () {
      expect(
        state(messages, const [
          ConversationReadMarker(userId: 'cy', lastReadMessageId: 'b'),
        ]).groupReadCount,
        0,
      );
    });

    test('a system notice from me is not "my newest message"', () {
      final withNotice = [
        ...messages,
        message('n', sender: 'me', at: at(4), type: MessageType.system),
      ];
      final result = state(withNotice, markers);
      expect(result.latestOutgoingMessageId, 'c');
      expect(result.groupReadCount, 2);
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
        readScope: ReadReceiptScope.none,
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
        readScope: ReadReceiptScope.none,
        search: (messages, query) => [
          for (final m in messages)
            if (m.body == query) m,
        ],
      );
      expect([for (final m in searched.display) m.id], ['b']);
      expect(searched.followUpIds, isEmpty);
      expect(searched.dayStartIds, isEmpty);
    });

    test('what the newest own message tells depends on the chat', () {
      final messages = [
        message('a', sender: 'me', at: at(0)),
        message('b', at: at(1)),
      ];
      const markers = [
        ConversationReadMarker(userId: 'other', lastReadMessageId: 'b'),
      ];
      ThreadLayout layout(ReadReceiptScope readScope) => ThreadLayout.build(
        messages: messages,
        readMarkers: markers,
        pending: const [],
        query: '',
        dividerId: null,
        currentUserId: 'me',
        forumPost: false,
        readScope: readScope,
        search: (messages, query) => messages,
      );
      final direct = layout(ReadReceiptScope.direct);
      expect(direct.latestOutgoingReadState.isRead, isTrue);
      expect(direct.readScope, ReadReceiptScope.direct);
      final group = layout(ReadReceiptScope.group);
      expect(group.latestOutgoingReadState.isRead, isFalse);
      expect(group.latestOutgoingReadState.groupReadCount, 1);
      expect(
        layout(
          ReadReceiptScope.none,
        ).latestOutgoingReadState.latestOutgoingMessageId,
        isNull,
      );
    });
  });
}
