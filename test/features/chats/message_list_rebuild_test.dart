import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/shared/models/chat_status.dart';

import 'mixed_thread_fixture.dart';

/// What rebuilds in a 1,000 message conversation when one thing changes:
/// the messages on screen must not rebuild for anything but their own
/// change. (Counts come from Flutter's own rebuild hook, so they are exact.)
void main() {
  late MixedThreadWorld world;

  Future<RebuildCounter> measure(
    WidgetTester tester,
    Future<void> Function() change,
  ) async {
    final counter = RebuildCounter()..start();
    await change();
    counter.stop();
    return counter;
  }

  Future<void> openMixed(WidgetTester tester) async {
    world = MixedThreadWorld();
    await world.open(tester);
    // The wallpaper, pictures and maps have arrived.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('chat-message-list')), findsOneWidget);
  }

  testWidgets('typing in the composer does not rebuild the message list', (
    tester,
  ) async {
    await openMixed(tester);
    final field = find.descendant(
      of: find.byKey(const ValueKey('chat-composer-field')),
      matching: find.byType(EditableText),
    );
    // The first characters swap the voice button for Send.
    await tester.enterText(field, 'he');
    await tester.pump();

    final counter = await measure(tester, () async {
      var text = 'he';
      for (final character in 'llo w'.split('')) {
        text += character;
        await tester.enterText(field, text);
        await tester.pump();
      }
    });

    debugPrint('typing 5 characters: ${counter.summary()}');
    expect(counter.of('_MessageBubble'), 0);
    expect(counter.of('MessageListView'), 0);
    expect(counter.of('ChatThreadScreen'), 0);
    // The composer itself is all that moves: about a hundred widgets a key
    // (a line that wraps makes the composer taller, which does rebuild the
    // screen once to keep the list clear of it; not tried here).
    expect(counter.total / 5, lessThan(120));
    await world.close(tester);
  });

  testWidgets('a reaction rebuilds only the message it is on', (tester) async {
    await openMixed(tester);
    const target = 'message-00998';
    world.repository.rows.firstWhere(
      (r) => r['id'] == target,
    )['reactions'] = const [
      {'emoji': '🎉', 'count': 3},
    ];

    final counter = await measure(tester, () async {
      world.repository.emit(
        const ThreadEvent(ThreadEventKind.reactionsChanged, messageId: target),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
    });

    debugPrint('one reaction changes: ${counter.summary()}');
    expect(find.text('🎉'), findsOneWidget);
    expect(counter.of('_MessageBubble'), 1);
    await world.close(tester);
  });

  testWidgets('an edit rebuilds only the message that was edited', (
    tester,
  ) async {
    await openMixed(tester);
    const target = 'message-00998';
    final row = world.repository.rows.firstWhere((r) => r['id'] == target);
    row['body'] = 'Edited body';
    row['edited_at'] = DateTime.utc(2027).toIso8601String();

    final counter = await measure(tester, () async {
      world.repository.emit(
        const ThreadEvent(ThreadEventKind.messageUpdated, messageId: target),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
    });

    debugPrint('one message is edited: ${counter.summary()}');
    expect(find.text('Edited body'), findsOneWidget);
    expect(counter.of('_MessageBubble'), 1);
    await world.close(tester);
  });

  testWidgets('presence and typing indicators do not rebuild the messages', (
    tester,
  ) async {
    await openMixed(tester);

    final counter = await measure(tester, () async {
      for (var i = 0; i < 6; i++) {
        world.online.add(i.isEven ? const {'user-2'} : const {'user-3'});
        await tester.pump();
        world.repository.emitActivity(
          ConversationActivity(
            typingUserIds: i.isEven ? const {'user-2'} : const {},
          ),
        );
        await tester.pump();
      }
    });

    debugPrint('presence and typing, 12 changes: ${counter.summary()}');
    expect(counter.of('_MessageBubble'), 0);
    await world.close(tester);
  });

  testWidgets('a new message builds one new bubble', (tester) async {
    await openMixed(tester);
    world.repository.rows = [
      ...world.repository.rows,
      {
        ...world.repository.rows.last,
        'id': 'message-new-1',
        'body': 'Fresh message',
        'created_at': DateTime.utc(2027, 2).toIso8601String(),
        'reactions': const <Object?>[],
      },
    ];

    final counter = await measure(tester, () async {
      world.repository.emit(
        const ThreadEvent(
          ThreadEventKind.messageInserted,
          messageId: 'message-new-1',
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pump();
    });

    debugPrint('a message arrives: ${counter.summary()}');
    expect(find.text('Fresh message'), findsOneWidget);
    // The new one, and the one before it (grouping looks at neighbours).
    expect(counter.of('_MessageBubble'), lessThanOrEqualTo(2));
    await world.close(tester);
  });
}
