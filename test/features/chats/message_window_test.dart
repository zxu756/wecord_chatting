import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/message_window.dart';
import 'package:wecord/shared/models/message.dart';

ChatMessage _message(int minute, {String? id, String body = ''}) {
  return ChatMessage(
    id: id ?? 'm${minute.toString().padLeft(3, '0')}',
    conversationId: 'conversation-1',
    senderId: 'user-2',
    type: MessageType.text,
    body: body.isEmpty ? 'Message $minute' : body,
    createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: minute)),
  );
}

List<ChatMessage> _range(int from, int to) => [
  for (var minute = from; minute <= to; minute++) _message(minute),
];

List<String> _ids(MessageWindow window) => [
  for (final message in window.messages) message.id,
];

void main() {
  group('MessageCursor', () {
    test('orders by time, then by id', () {
      final time = DateTime.utc(2026, 1, 1);
      expect(
        MessageCursor(time, 'a').isBefore(MessageCursor(time, 'b')),
        isTrue,
      );
      expect(
        MessageCursor(time, 'z').isBefore(
          MessageCursor(time.add(const Duration(microseconds: 1)), 'a'),
        ),
        isTrue,
      );
    });

    test('queries with the server timestamp when it has one', () {
      final cursor = MessageCursor(
        DateTime.utc(2026, 1, 1),
        'a',
        timestamp: '2026-01-01T00:00:00.123456+00:00',
      );
      expect(cursor.queryTimestamp, '2026-01-01T00:00:00.123456+00:00');
      expect(
        MessageCursor(DateTime.utc(2026, 1, 1), 'a').queryTimestamp,
        '2026-01-01T00:00:00.000Z',
      );
    });
  });

  group('pages', () {
    test('a full newest page may have older messages', () {
      final window = MessageWindow.latest(_range(51, 100), limit: 50);
      expect(window.hasOlder, isTrue);
      expect(window.hasNewer, isFalse);
      expect(window.isLive, isTrue);
      expect(window.messages.first.id, 'm051');

      final short = MessageWindow.latest(_range(1, 10), limit: 50);
      expect(short.hasOlder, isFalse);
    });

    test('pages come in any order and are kept oldest first, once', () {
      final window = MessageWindow.latest(
        [..._range(51, 100)].reversed.toList(),
        limit: 50,
      );
      expect(window.messages.first.id, 'm051');
      expect(window.messages.last.id, 'm100');
    });

    test('older pages prepend until the start is reached', () {
      var window = MessageWindow.latest(_range(51, 100), limit: 50);
      window = window.withOlder(_range(1, 50), limit: 50);
      expect(window.messages, hasLength(100));
      expect(window.messages.first.id, 'm001');
      expect(window.hasOlder, isTrue, reason: 'a full page may have more');

      window = window.withOlder(const [], limit: 50);
      expect(window.hasOlder, isFalse);
      expect(window.messages, hasLength(100));
    });

    test('an overlapping older page does not duplicate', () {
      var window = MessageWindow.latest(_range(51, 100), limit: 50);
      window = window.withOlder(_range(40, 55), limit: 50);
      expect(window.messages, hasLength(61));
      expect(_ids(window).toSet(), hasLength(61));
      expect(window.hasOlder, isFalse);
    });

    test('the window around a message is detached from the latest', () {
      final window = MessageWindow.around(
        _message(500),
        before: _range(475, 499),
        after: _range(501, 525),
        limit: 25,
      );
      expect(window.messages, hasLength(51));
      expect(window.hasOlder, isTrue);
      expect(window.hasNewer, isTrue);
      expect(window.isLive, isFalse);

      final caughtUp = window.withNewer(_range(526, 530), limit: 25);
      expect(caughtUp.hasNewer, isFalse);
      expect(caughtUp.messages.last.id, 'm530');
    });

    test('the earliest page of a forum post may have newer messages', () {
      final window = MessageWindow.earliest(_range(1, 50), limit: 50);
      expect(window.hasNewer, isTrue);
      expect(window.hasOlder, isFalse);
    });
  });

  group('realtime changes', () {
    test('new messages join a live window at the end', () {
      final window = MessageWindow.latest(_range(51, 100), limit: 50);
      final next = window.upsert([_message(101), _message(102)]);
      expect(next.messages.last.id, 'm102');
      expect(next.messages, hasLength(52));
      // The loaded messages are reused as they are.
      expect(identical(next.messages.first, window.messages.first), isTrue);
    });

    test('new messages stay out of a window detached from the latest', () {
      final window = MessageWindow.around(
        _message(500),
        before: _range(475, 499),
        after: _range(501, 525),
        limit: 25,
      );
      expect(identical(window.upsert([_message(900)]), window), isTrue);
    });

    test('messages older than a window with more history stay out', () {
      final window = MessageWindow.latest(_range(51, 100), limit: 50);
      expect(window.upsert([_message(10)]).messages, hasLength(50));

      final whole = MessageWindow.latest(_range(51, 60), limit: 50);
      expect(whole.upsert([_message(10)]).messages.first.id, 'm010');
    });

    test('edits replace the loaded message in place', () {
      final window = MessageWindow.latest(_range(1, 10), limit: 50);
      final edited = _message(5, body: 'Edited');
      final next = window.upsert([edited]);
      expect(next.messages, hasLength(10));
      expect(next.byId('m005')!.body, 'Edited');
      expect(next.messages[4], same(edited));
      expect(next.messages[3], same(window.messages[3]));
    });

    test('a late message in the middle is put in order', () {
      final window = MessageWindow.latest([
        _message(1),
        _message(3),
      ], limit: 50);
      final next = window.upsert([_message(2)]);
      expect(_ids(next), ['m001', 'm002', 'm003']);
    });

    test('deletes drop the message', () {
      final window = MessageWindow.latest(_range(1, 5), limit: 50);
      final next = window.remove(['m003', 'unknown']);
      expect(_ids(next), ['m001', 'm002', 'm004', 'm005']);
      expect(identical(window.remove(['unknown']), window), isTrue);
    });

    test('finds a message by the client id it was sent with', () {
      final sent = ChatMessage(
        id: 'server-id',
        conversationId: 'conversation-1',
        senderId: 'user-1',
        type: MessageType.text,
        body: 'Hello',
        createdAt: DateTime.utc(2026, 1, 2),
        clientId: 'client-1',
      );
      final window = MessageWindow.latest([..._range(1, 3), sent], limit: 50);
      expect(window.byClientId('client-1'), same(sent));
      expect(window.byClientId('client-2'), isNull);
    });
  });

  group('syncing a cached window', () {
    test('a page that overlaps keeps the older cached messages', () {
      // Cached: 1–100. Server's newest page: 61–110 (61–100 unchanged,
      // 75 deleted, 101–110 new).
      final cached = MessageWindow(messages: _range(1, 100), hasOlder: true);
      final latest = [
        for (final message in _range(61, 110))
          if (message.id != 'm075') message,
      ];

      final synced = cached.syncWithLatest(latest, limit: 49);

      expect(synced.messages.first.id, 'm001');
      expect(synced.messages.last.id, 'm110');
      expect(synced.byId('m075'), isNull);
      expect(synced.messages, hasLength(109));
      expect(synced.hasOlder, isTrue);
      expect(synced.isLive, isTrue);
    });

    test('a gap between the cache and the newest page starts over', () {
      final cached = MessageWindow(messages: _range(1, 50), hasOlder: false);
      final latest = _range(200, 249);

      final synced = cached.syncWithLatest(latest, limit: 50);

      expect(synced.messages.first.id, 'm200');
      expect(synced.messages, hasLength(50));
      expect(synced.hasOlder, isTrue);
    });

    test('a short newest page is the whole conversation', () {
      final cached = MessageWindow(messages: _range(1, 30), hasOlder: true);
      final latest = [
        for (final message in _range(1, 32))
          if (message.id != 'm010') message,
      ];

      final synced = cached.syncWithLatest(latest, limit: 50);

      expect(synced.messages, hasLength(31));
      expect(synced.byId('m010'), isNull);
      expect(synced.hasOlder, isFalse);
    });

    test('an empty conversation empties the cache', () {
      final cached = MessageWindow(messages: _range(1, 30), hasOlder: true);
      expect(cached.syncWithLatest(const [], limit: 50).isEmpty, isTrue);
    });

    test('a span replaced by a fresh page drops what it lacks', () {
      final window = MessageWindow.latest(_range(1, 20), limit: 50);
      final fresh = [
        for (final message in _range(5, 10))
          if (message.id != 'm007') message,
      ];
      final next = window.replaceSpan(fresh);
      expect(next.byId('m007'), isNull);
      expect(next.messages, hasLength(19));
      expect(next.messages.first.id, 'm001');
    });

    test('the cache keeps the newest messages', () {
      final window = MessageWindow.latest(_range(1, 150), limit: 200);
      final newest = window.newestMessages(100);
      expect(newest, hasLength(100));
      expect(newest.first.id, 'm051');
      expect(newest.last.id, 'm150');
    });
  });
}
