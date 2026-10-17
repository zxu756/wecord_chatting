import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/pat/pat_repository.dart';

import '../../mobile/phone_test_support.dart';
import 'pat_fakes.dart';

/// Bart's avatar next to his last message (the forwarded one).
final _bartAvatar = find.byKey(const ValueKey('message-avatar-m6'));

/// Where the avatar is next to its message, over a short while after
/// [action], frame by frame. Measured against the message beside it, because
/// new lines move the whole list.
Future<List<Offset>> _avatarPath(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  Offset sway() =>
      tester.getTopLeft(_bartAvatar) -
      tester.getTopLeft(find.text('Forwarding this one.'));
  final path = <Offset>[sway()];
  await action();
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 60));
    path.add(sway());
  }
  return path;
}

bool _moved(List<Offset> path) => path.any((point) => point != path.first);

void main() {
  late PhoneWorld world;
  late FakePatRepository pats;

  setUp(() {
    world = PhoneWorld();
    pats = FakePatRepository();
    world.extraOverrides = patOverrides(pats);
  });

  group('the pat line', () {
    testWidgets('reads from each side of the pat', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(
        tester,
        world,
        extra: [
          patMessage(
            'pat-mine',
            actorId: 'user-1',
            targetId: 'user-2',
            suffix: "'s shoulder",
            age: const Duration(minutes: 5),
          ),
          patMessage(
            'pat-theirs',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
            suffix: "'s shoulder",
            age: const Duration(minutes: 4),
          ),
          patMessage(
            'pat-undone',
            actorId: 'user-1',
            targetId: 'user-2',
            undone: true,
            age: const Duration(minutes: 3),
          ),
        ],
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pat-line-pat-mine')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text("You patted Bart's shoulder"), findsOneWidget);
      expect(find.text('Bart patted your shoulder'), findsOneWidget);
      expect(find.text('You took back a pat'), findsOneWidget);
      // Too old to take back, so no Undo anywhere.
      expect(find.byKey(const ValueKey('pat-undo')), findsNothing);
      await world.close(tester);
    });

    testWidgets('the patter can take it back for 2 minutes', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(
        tester,
        world,
        extra: [patMessage('pat-fresh', actorId: 'user-1', targetId: 'user-2')],
      );

      expect(find.text('You patted Bart'), findsOneWidget);
      expect(find.byKey(const ValueKey('pat-undo')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pat-undo')));
      await settle(tester);

      expect(pats.undone, ['pat-fresh']);
      await world.close(tester);
    });

    testWidgets('Undo goes away on its own once the 2 minutes are over', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(
        tester,
        world,
        extra: [
          patMessage(
            'pat-fresh',
            actorId: 'user-1',
            targetId: 'user-2',
            age: const Duration(seconds: 118),
          ),
        ],
      );
      expect(find.byKey(const ValueKey('pat-undo')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byKey(const ValueKey('pat-undo')), findsNothing);
      await world.close(tester);
    });

    testWidgets('the receiver gets no Undo', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(
        tester,
        world,
        extra: [
          patMessage(
            'pat-in',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
          ),
        ],
      );
      expect(find.text('Bart patted you'), findsOneWidget);
      expect(find.byKey(const ValueKey('pat-undo')), findsNothing);
      await world.close(tester);
    });

    testWidgets('a pat taken back too late says so', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.failUndo = PatFailure.undoExpired;
      await openChatWithPats(
        tester,
        world,
        extra: [patMessage('pat-fresh', actorId: 'user-1', targetId: 'user-2')],
      );

      await tester.tap(find.byKey(const ValueKey('pat-undo')));
      await settle(tester);

      expect(find.text("It's too late to take that pat back."), findsOneWidget);
      await world.close(tester);
    });
  });

  group('double tapping an avatar', () {
    testWidgets('pats that person', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      await tester.tap(_bartAvatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(pats.pats, [(conversationId: 'dm-1', userId: 'user-2')]);
      // And it is not a quick reaction on his message.
      expect(world.chats.toggledReactions, isEmpty);
      await world.close(tester);
    });

    testWidgets('one tap does nothing', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(pats.pats, isEmpty);
      await world.close(tester);
    });

    testWidgets('the avatar shakes gently at once', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      final path = await _avatarPath(tester, () async {
        await tester.tap(_bartAvatar);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(_bartAvatar);
      });

      expect(_moved(path), isTrue);
      // Gentle: a few pixels, and back where it was.
      for (final point in path) {
        expect((point - path.first).distance, lessThan(8));
      }
      await settle(tester);
      expect(
        tester.getTopLeft(_bartAvatar) -
            tester.getTopLeft(find.text('Forwarding this one.')),
        path.first,
      );
      await world.close(tester);
    });

    testWidgets('too quick a second pat is said gently', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.failPat = PatFailure.tooFast;
      await openChatWithPats(tester, world);

      await tester.tap(_bartAvatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(
        find.text('You just patted them. Try again in a moment.'),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('too many pats an hour are said too', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.failPat = PatFailure.tooMany;
      await openChatWithPats(tester, world);

      await tester.tap(_bartAvatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(
        find.text('That is a lot of pats. Try again later.'),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a blocked person cannot be patted', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.failPat = PatFailure.notAllowed;
      await openChatWithPats(tester, world);

      await tester.tap(_bartAvatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(find.text("You can't pat them here."), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('works in a group chat', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.chats.messages = [
        for (final message in richMessages())
          message.copyWith(conversationId: 'group-1'),
      ];
      await world.open(tester, '/chats/group-1');

      await tester.tap(_bartAvatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_bartAvatar);
      await settle(tester);

      expect(pats.pats, [(conversationId: 'group-1', userId: 'user-2')]);
      await world.close(tester);
    });

    testWidgets('does nothing in circle channels', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      world.chats.messages = richMessages();
      await world.open(tester, '/circles/circle-1/channels/conv-general');
      final avatar = find.byKey(const ValueKey('message-avatar-m6'));
      await tester.ensureVisible(avatar);

      await tester.tap(avatar);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(avatar);
      await settle(tester);

      expect(pats.pats, isEmpty);
      await world.close(tester);
    });
  });

  group('being patted', () {
    testWidgets('shakes the patter\'s avatar when the chat is open', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      final path = await _avatarPath(tester, () async {
        world.chats.messages = [
          ...world.chats.messages,
          patMessage(
            'pat-in',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
            age: const Duration(seconds: 1),
          ),
        ];
        world.chats.emitMessageChange();
      });

      expect(find.text('Bart patted you'), findsOneWidget);
      expect(_moved(path), isTrue);
      await world.close(tester);
    });

    testWidgets('a muted chat gets the line but no shake', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world, muted: true);

      final path = await _avatarPath(tester, () async {
        world.chats.messages = [
          ...world.chats.messages,
          patMessage(
            'pat-in',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
            age: const Duration(seconds: 1),
          ),
        ];
        world.chats.emitMessageChange();
      });

      expect(find.text('Bart patted you'), findsOneWidget);
      expect(_moved(path), isFalse);
      await world.close(tester);
    });

    testWidgets('an old pat does not shake anything when the chat opens', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(
        tester,
        world,
        extra: [
          patMessage(
            'pat-old',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
            age: const Duration(minutes: 10),
          ),
        ],
      );
      final path = await _avatarPath(tester, () async {});
      expect(_moved(path), isFalse);
      await world.close(tester);
    });

    testWidgets('a pat that was taken back does not shake', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      final path = await _avatarPath(tester, () async {
        world.chats.messages = [
          ...world.chats.messages,
          patMessage(
            'pat-in',
            actorId: 'user-2',
            targetId: 'user-1',
            actorName: 'Bart',
            targetName: 'Ada',
            undone: true,
            age: const Duration(seconds: 1),
          ),
        ];
        world.chats.emitMessageChange();
      });
      expect(_moved(path), isFalse);
      await world.close(tester);
    });

    testWidgets('a pat for someone else does not shake', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      await openChatWithPats(tester, world);

      final path = await _avatarPath(tester, () async {
        world.chats.messages = [
          ...world.chats.messages,
          patMessage(
            'pat-other',
            actorId: 'user-2',
            targetId: 'user-3',
            actorName: 'Bart',
            targetName: 'Grace',
            age: const Duration(seconds: 1),
          ),
        ];
        world.chats.emitMessageChange();
      });
      expect(_moved(path), isFalse);
      await world.close(tester);
    });
  });

  group('the pat suffix', () {
    testWidgets('is set in Settings and shown there', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.currentSuffix = "'s shoulder";
      await world.open(tester, '/me');

      expect(find.text('Pat suffix'), findsOneWidget);
      expect(find.text("'s shoulder"), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pat-suffix-row')));
      await settle(tester);
      expect(find.byKey(const ValueKey('pat-suffix-sheet')), findsOneWidget);
      // How it reads to friends.
      expect(find.text("Bart patted Ada Lovelace's shoulder"), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('pat-suffix-field')),
        "'s hand",
      );
      await tester.pump();
      expect(find.text("Bart patted Ada Lovelace's hand"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pat-suffix-save')));
      await settle(tester);

      expect(pats.savedSuffixes, ["'s hand"]);
      expect(find.byKey(const ValueKey('pat-suffix-sheet')), findsNothing);
      expect(find.text("'s hand"), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('an idea fills the field, and it can be cleared', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      pats.currentSuffix = "'s shoulder";
      await world.open(tester, '/me');
      await tester.tap(find.byKey(const ValueKey('pat-suffix-row')));
      await settle(tester);

      await tester.tap(find.text("'s head"));
      await tester.pump();
      expect(find.text("Bart patted Ada Lovelace's head"), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('pat-suffix-field')),
        '',
      );
      await tester.pump();
      expect(find.text('Bart patted Ada Lovelace'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pat-suffix-save')));
      await settle(tester);

      expect(pats.savedSuffixes, ['']);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('pat-suffix-row')),
          matching: find.text('None'),
        ),
        findsOneWidget,
      );
      await world.close(tester);
    });

    testWidgets('a failed save says so and keeps the sheet', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      pats.failSetSuffix = StateError('offline');
      await world.open(tester, '/me');
      await tester.tap(find.byKey(const ValueKey('pat-suffix-row')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('pat-suffix-save')));
      await settle(tester);

      expect(find.text("Couldn't save the suffix. Try again."), findsOneWidget);
      expect(find.byKey(const ValueKey('pat-suffix-sheet')), findsOneWidget);
      await world.close(tester);
    });
  });
}
