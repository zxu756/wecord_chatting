import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/features/chats/selection/selection_rules.dart';
import 'package:wecord/shared/models/message.dart';

ChatMessage _message(
  String id, {
  MessageType type = MessageType.text,
  String body = 'hello',
  String senderId = 'user-2',
  int minute = 0,
  Map<String, dynamic>? attachment,
  DateTime? recalledAt,
  DateTime? expiresAt,
  MessageReviewState? reviewState,
  List<ChatMessage>? album,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    senderId: senderId,
    type: type,
    body: body,
    createdAt: DateTime.utc(2026, 10, 18, 9, minute),
    attachment: attachment,
    recalledAt: recalledAt,
    expiresAt: expiresAt,
    reviewState: reviewState,
    album: album,
  );
}

void main() {
  group('canForwardMessage', () {
    test('plain messages, pictures, files and voice go', () {
      expect(canForwardMessage(_message('a')), isTrue);
      expect(
        canForwardMessage(
          _message(
            'a',
            type: MessageType.image,
            attachment: {'kind': 'image', 'view_once': false},
          ),
        ),
        isTrue,
      );
      expect(canForwardMessage(_message('a', type: MessageType.file)), isTrue);
      expect(canForwardMessage(_message('a', type: MessageType.voice)), isTrue);
    });

    test('what forward_message refuses stays out', () {
      expect(canForwardMessage(_message('a', type: MessageType.poll)), isFalse);
      expect(
        canForwardMessage(_message('a', type: MessageType.sticker)),
        isFalse,
      );
      expect(
        canForwardMessage(_message('a', type: MessageType.system)),
        isFalse,
      );
      expect(
        canForwardMessage(_message('a', recalledAt: DateTime.utc(2026))),
        isFalse,
      );
      expect(
        canForwardMessage(_message('a', reviewState: MessageReviewState.held)),
        isFalse,
      );
    });

    test('view-once media and expired messages stay out', () {
      expect(
        canForwardMessage(
          _message(
            'a',
            type: MessageType.image,
            attachment: {'kind': 'image', 'view_once': true},
          ),
        ),
        isFalse,
      );
      final now = DateTime.utc(2026, 10, 18, 12);
      expect(
        canForwardMessage(
          _message('a', expiresAt: now.subtract(const Duration(minutes: 1))),
          now: now,
        ),
        isFalse,
      );
      // A message that has not expired yet can go.
      expect(
        canForwardMessage(
          _message('a', expiresAt: now.add(const Duration(hours: 1))),
          now: now,
        ),
        isTrue,
      );
    });

    test('a message still sending cannot go', () {
      expect(canForwardMessage(_message('outbox:abc')), isFalse);
    });
  });

  group('copyTextOfSelection', () {
    String name(ChatMessage message) =>
        message.senderId == 'user-1' ? 'You' : 'Ada';

    test('one text message is copied as it is', () {
      expect(
        copyTextOfSelection([
          _message('a', body: ' hi **there** '),
        ], nameOf: name),
        'hi **there**',
      );
    });

    test('several are copied as name: text lines, oldest first', () {
      expect(
        copyTextOfSelection([
          _message('a', body: 'Meet at 7?'),
          _message('b', body: 'Yes', senderId: 'user-1'),
        ], nameOf: name),
        'Ada: Meet at 7?\nYou: Yes',
      );
    });

    test('pictures, cards and empty messages add nothing', () {
      expect(
        copyTextOfSelection([
          _message('a', type: MessageType.image),
        ], nameOf: name),
        isNull,
      );
      expect(
        copyTextOfSelection([
          _message(
            'a',
            body: 'Chat history: x',
            attachment: {'kind': 'chat_history'},
          ),
          _message('b', body: '  '),
        ], nameOf: name),
        isNull,
      );
      expect(
        copyTextOfSelection([
          _message('a', type: MessageType.image),
          _message('b', body: 'caption text'),
        ], nameOf: name),
        'Ada: caption text',
      );
    });
  });

  group('canDeleteSelection', () {
    final own = _message('a', senderId: 'user-1');
    final theirs = _message('b');

    test('my own messages can go', () {
      expect(
        canDeleteSelection(
          [own],
          currentUserId: 'user-1',
          canModerate: (_) => false,
        ),
        isTrue,
      );
    });

    test('someone else\'s need moderation', () {
      expect(
        canDeleteSelection(
          [own, theirs],
          currentUserId: 'user-1',
          canModerate: (_) => false,
        ),
        isFalse,
      );
      expect(
        canDeleteSelection(
          [own, theirs],
          currentUserId: 'user-1',
          canModerate: (_) => true,
        ),
        isTrue,
      );
    });

    test(
      'nothing selected, system lines and deleted messages do not count',
      () {
        expect(
          canDeleteSelection(
            const [],
            currentUserId: 'user-1',
            canModerate: (_) => true,
          ),
          isFalse,
        );
        expect(
          canDeleteSelection(
            [_message('s', type: MessageType.system, senderId: 'user-1')],
            currentUserId: 'user-1',
            canModerate: (_) => true,
          ),
          isFalse,
        );
      },
    );
  });

  group('the selection controller', () {
    late ProviderContainer container;
    late ChatSelectionController controller;
    ChatSelectionState state() => container.read(chatSelectionProvider('c1'));

    setUp(() {
      container = ProviderContainer();
      container.listen(chatSelectionProvider('c1'), (_, _) {});
      controller = container.read(chatSelectionProvider('c1').notifier);
    });
    tearDown(() => container.dispose());

    test('starts out of selection mode', () {
      expect(state().active, isFalse);
      expect(state().count, 0);
    });

    test('begin ticks the message and starts the mode', () {
      controller.begin(_message('a'));
      expect(state().active, isTrue);
      expect(state().isSelected('a'), isTrue);
      expect(state().count, 1);
    });

    test('toggle ticks and unticks, and stays in the mode when empty', () {
      controller
        ..begin(_message('a'))
        ..toggle(_message('b'))
        ..toggle(_message('a'));
      expect(state().messages.keys, ['b']);
      controller.toggle(_message('b'));
      expect(state().count, 0);
      expect(state().active, isTrue);
    });

    test('ordered gives the selection oldest first', () {
      controller
        ..begin(_message('late', minute: 9))
        ..toggle(_message('early', minute: 1))
        ..toggle(_message('middle', minute: 5));
      expect(state().ordered.map((m) => m.id), ['early', 'middle', 'late']);
    });

    test('system lines, deleted and sending messages cannot be ticked', () {
      controller
        ..begin(_message('a'))
        ..toggle(_message('s', type: MessageType.system))
        ..toggle(_message('d', recalledAt: DateTime.utc(2026)))
        ..toggle(_message('outbox:x'));
      expect(state().messages.keys, ['a']);
    });

    test('an album is ticked and unticked as a whole', () {
      final pictures = [
        for (var i = 1; i <= 3; i++) _message('p$i', type: MessageType.image),
      ];
      final entry = pictures.first.copyWith(album: pictures);
      controller.begin(entry);
      expect(state().count, 3);
      expect(state().isEntrySelected(entry), isTrue);
      controller.toggle(entry);
      expect(state().count, 0);
    });

    test('at most $maxSelectedMessages can be ticked', () {
      controller.begin(_message('m0'));
      for (var i = 1; i < maxSelectedMessages; i++) {
        expect(controller.toggle(_message('m$i')), isTrue);
      }
      expect(state().count, maxSelectedMessages);
      expect(controller.toggle(_message('one-too-many')), isFalse);
      expect(state().count, maxSelectedMessages);
      // Unticking still works.
      expect(controller.toggle(_message('m0')), isTrue);
    });

    test('selectAll ticks a range as far as there is room', () {
      controller.begin(_message('m0'));
      final range = [for (var i = 1; i < 130; i++) _message('m$i')];
      expect(controller.selectAll(range, anchorId: 'm129'), isFalse);
      expect(state().count, maxSelectedMessages);
      expect(state().anchorId, 'm129');
    });

    test('cancel leaves the mode and forgets the selection', () {
      controller
        ..begin(_message('a'))
        ..cancel();
      expect(state().active, isFalse);
      expect(state().count, 0);
    });
  });
}
