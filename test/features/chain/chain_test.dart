import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chain/chain_card.dart';
import 'package:wecord/features/chain/chain_create_sheet.dart';
import 'package:wecord/features/chain/chain_models.dart';
import 'package:wecord/features/chain/chain_repository.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import 'chain_fakes.dart';

Widget host(FakeChainRepository repository, Widget child) {
  return ProviderScope(
    overrides: [chainRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(
        body: Center(child: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

const _card = ChainCard(chainId: 'chain-1', title: 'Saturday hike sign-up');

Future<void> pumpCard(
  WidgetTester tester,
  FakeChainRepository repository,
) async {
  await tester.pumpWidget(host(repository, const ChainCardView(card: _card)));
  await tester.pump();
  await tester.pump();
}

/// A tall screen, so the lazily built sheets keep all their rows.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('models', () {
    test('a snapshot parses the server answer', () {
      final chain = ChainSnapshot.fromJson({
        'id': 'c1',
        'conversation_id': 'conv',
        'message_id': 'm1',
        'title': 'Hike',
        'description': 'Meet at 8',
        'example': '1. Ada',
        'deadline': '2026-10-20T12:00:00+00:00',
        'max_entries': 3,
        'entry_count': 2,
        'closed': false,
        'created_by': 'u1',
        'creator_name': 'Ada',
        'can_manage': true,
        'my_entry_id': 'e2',
        'entries': [
          {'id': 'e1', 'user_id': 'u1', 'name': 'Ada', 'note': ''},
          {'id': 'e2', 'user_id': 'u2', 'name': 'Bob', 'note': 'snacks'},
          'broken',
        ],
      });
      expect(chain.entries.map((e) => e.text), ['Ada', 'Bob snacks']);
      expect(chain.myEntry?.name, 'Bob');
      expect(chain.canManage, isTrue);
      expect(chain.maxEntries, 3);
      expect(chain.isFull, isFalse);
      expect(chain.seatsLeft, 1);
      expect(chain.deadline, DateTime.utc(2026, 10, 20, 12));
    });

    test('a chain is closed by hand or by its deadline', () {
      ChainSnapshot chain({bool closed = false, DateTime? deadline}) {
        return ChainSnapshot(
          id: 'c',
          conversationId: 'conv',
          title: 't',
          createdBy: 'u',
          entries: const [],
          closedByServer: closed,
          deadline: deadline,
        );
      }

      final now = DateTime.utc(2026, 10, 18, 12);
      expect(chain().isClosed(now), isFalse);
      expect(chain(closed: true).isClosed(now), isTrue);
      expect(
        chain(deadline: now.add(const Duration(minutes: 1))).isClosed(now),
        isFalse,
      );
      expect(chain(deadline: now).isClosed(now), isTrue);
      expect(
        chain(deadline: now.subtract(const Duration(days: 1))).isClosed(now),
        isTrue,
      );
    });

    test('the list exports as numbered plain text', () {
      final chain = ChainSnapshot(
        id: 'c',
        conversationId: 'conv',
        title: 'Saturday hike sign-up',
        createdBy: 'u',
        entries: const [
          ChainEntry(id: 'a', userId: 'u1', name: 'Ada', note: 'bring snacks'),
          ChainEntry(id: 'b', userId: 'u2', name: 'Bob'),
        ],
      );
      expect(
        chain.exportText(),
        'Saturday hike sign-up\n1. Ada bring snacks\n2. Bob',
      );
      expect(
        ChainSnapshot(
          id: 'c',
          conversationId: 'conv',
          title: 'Empty',
          createdBy: 'u',
          entries: const [],
        ).exportText(),
        'Empty\nNobody has joined yet.',
      );
    });

    test('only a chain attachment on a live text message is a card', () {
      ChatMessage message({
        Map<String, dynamic>? attachment,
        DateTime? recalledAt,
        MessageType type = MessageType.text,
      }) {
        return ChatMessage(
          id: 'm',
          conversationId: 'conv',
          senderId: 'u',
          type: type,
          body: 'x',
          createdAt: DateTime.utc(2026, 10, 18),
          attachment: attachment,
          recalledAt: recalledAt,
        );
      }

      const chain = {'kind': 'chain', 'chain_id': 'c1', 'title': 'Hike'};
      expect(message(attachment: chain).chainCard?.chainId, 'c1');
      expect(message(attachment: chain).chainCard?.title, 'Hike');
      expect(message().chainCard, isNull);
      expect(message(attachment: {'kind': 'note'}).chainCard, isNull);
      expect(message(attachment: {'kind': 'chain'}).chainCard, isNull);
      expect(
        message(attachment: chain, recalledAt: DateTime.utc(2026)).chainCard,
        isNull,
      );
    });

    test('the server\'s refusals become kinds with a message', () {
      ChainFailureKind kind(String message, {String? code}) =>
          ChainException.fromPostgrest(
            PostgrestException(message: message, code: code),
          ).kind;
      expect(kind('chain_closed'), ChainFailureKind.closed);
      expect(kind('chain_full'), ChainFailureKind.full);
      expect(kind('chain_already_joined'), ChainFailureKind.alreadyJoined);
      expect(kind('chain_not_joined'), ChainFailureKind.notJoined);
      expect(kind('chain_not_allowed'), ChainFailureKind.notAllowed);
      expect(kind('chain_text_too_long'), ChainFailureKind.tooLong);
      expect(kind('chain_deadline_invalid'), ChainFailureKind.badDeadline);
      expect(kind('Chain not found'), ChainFailureKind.gone);
      expect(kind('nope', code: '42501'), ChainFailureKind.forbidden);
      expect(kind('boom'), ChainFailureKind.other);
      expect(
        const ChainException(ChainFailureKind.full).message,
        'This chain is full.',
      );
    });
  });

  group('chain card', () {
    testWidgets('shows the numbered list and my own line', (tester) async {
      final repository = FakeChainRepository(description: 'Meet at the gate.')
        ..add('user-2', 'Ada', 'bring snacks')
        ..add('user-1', 'Me');
      await pumpCard(tester, repository);

      expect(find.text('Saturday hike sign-up'), findsOneWidget);
      expect(find.text('Meet at the gate.'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(
        find.textContaining('bring snacks', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('2 joined'), findsOneWidget);
      // I am in: the card offers to edit my line, not to join.
      expect(find.byKey(const ValueKey('chain-edit-chain-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsNothing);
      await unmount(tester);
    });

    testWidgets('long lists show the first lines and a count', (tester) async {
      final repository = FakeChainRepository();
      for (var i = 1; i <= 9; i++) {
        repository.add('u$i', 'Person $i');
      }
      await pumpCard(tester, repository);

      expect(find.text('6.'), findsOneWidget);
      expect(find.text('7.'), findsNothing);
      expect(find.text('and 3 more'), findsOneWidget);
      expect(find.text('9 joined'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an empty chain invites the first line', (tester) async {
      final repository = FakeChainRepository(example: '1. Ada +1');
      await pumpCard(tester, repository);

      expect(
        find.text('Nobody has joined yet. Example: 1. Ada +1'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Join asks for an optional note, adds the line, and shows it', (
      tester,
    ) async {
      final repository = FakeChainRepository()..add('user-2', 'Ada');
      await pumpCard(tester, repository);

      await tester.tap(find.byKey(const ValueKey('chain-join-chain-1')));
      await tester.pumpAndSettle();
      expect(find.text('Join the chain'), findsOneWidget);
      expect(find.text('You will be number 2.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('chain-note-field')),
        'bringing water',
      );
      await tester.tap(find.byKey(const ValueKey('chain-note-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, contains('join:bringing water'));
      expect(find.text('Join the chain'), findsNothing);
      expect(find.text('2.'), findsOneWidget);
      expect(
        find.textContaining('bringing water', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chain-edit-chain-1')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a note the circle holds back is explained', (tester) async {
      final repository = FakeChainRepository()..holdNotes = true;
      await pumpCard(tester, repository);

      await tester.tap(find.byKey(const ValueKey('chain-join-chain-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chain-note-field')),
        'buy my coins',
      );
      await tester.tap(find.byKey(const ValueKey('chain-note-save')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Your line is in, without the note: this circle reviews what new members write.',
        ),
        findsOneWidget,
      );
      expect(repository.entries.single.note, '');
      await unmount(tester);
    });

    testWidgets('I can edit and remove my own line', (tester) async {
      final repository = FakeChainRepository()..add('user-1', 'Me', 'maybe');
      await pumpCard(tester, repository);

      await tester.tap(find.byKey(const ValueKey('chain-edit-chain-1')));
      await tester.pumpAndSettle();
      expect(find.text('Your line'), findsOneWidget);
      final field = find.byKey(const ValueKey('chain-note-field'));
      expect(tester.widget<TextField>(field).controller!.text, 'maybe');
      await tester.enterText(field, 'definitely');
      await tester.tap(find.byKey(const ValueKey('chain-note-save')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('update:definitely'));
      expect(
        find.textContaining('definitely', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('chain-edit-chain-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chain-note-remove')));
      await tester.pumpAndSettle();
      expect(repository.calls, contains('leave'));
      expect(repository.entries, isEmpty);
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a closed chain takes no more lines', (tester) async {
      final repository = FakeChainRepository(closed: true)
        ..add('user-2', 'Ada');
      await pumpCard(tester, repository);

      expect(find.text('Closed'), findsOneWidget);
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsNothing);
      expect(find.byKey(const ValueKey('chain-edit-chain-1')), findsNothing);
      await unmount(tester);
    });

    testWidgets('a deadline that passed closes the card by itself', (
      tester,
    ) async {
      final repository = FakeChainRepository(
        deadline: DateTime.now().subtract(const Duration(minutes: 1)),
      )..add('user-2', 'Ada');
      await pumpCard(tester, repository);

      expect(find.text('Closed'), findsOneWidget);
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsNothing);
      await unmount(tester);
    });

    testWidgets('an open deadline is named on the card', (tester) async {
      final repository = FakeChainRepository(
        deadline: DateTime.now().add(const Duration(days: 2, hours: 1)),
      );
      await pumpCard(tester, repository);

      expect(find.textContaining('Closes '), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a full chain says so', (tester) async {
      final repository = FakeChainRepository(maxEntries: 2)
        ..add('user-2', 'Ada')
        ..add('user-3', 'Bob');
      await pumpCard(tester, repository);

      expect(find.text('Full'), findsOneWidget);
      expect(find.text('2 of 2 joined'), findsOneWidget);
      expect(find.byKey(const ValueKey('chain-join-chain-1')), findsNothing);
      await unmount(tester);
    });

    testWidgets('a server refusal is shown, not swallowed', (tester) async {
      final repository = FakeChainRepository(maxEntries: 1);
      await pumpCard(tester, repository);
      // Somebody took the last seat while the sheet was open.
      await tester.tap(find.byKey(const ValueKey('chain-join-chain-1')));
      await tester.pumpAndSettle();
      repository.add('user-9', 'Quick');
      await tester.tap(find.byKey(const ValueKey('chain-note-save')));
      await tester.pumpAndSettle();

      expect(find.text('This chain is full.'), findsWidgets);
      await unmount(tester);
    });

    testWidgets('the card follows the chain live, without a new message', (
      tester,
    ) async {
      final repository = FakeChainRepository()..add('user-2', 'Ada');
      await pumpCard(tester, repository);
      expect(find.text('1 joined'), findsOneWidget);

      repository
        ..add('user-3', 'Cy', 'plus one')
        ..touch();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('2 joined'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(
        find.textContaining('plus one', findRichText: true),
        findsOneWidget,
      );

      // A line removed by the creator disappears the same way.
      repository.entries.removeAt(0);
      repository.touch();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('1 joined'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a chain that cannot be read offers to try again', (
      tester,
    ) async {
      final repository = FakeChainRepository()..getError = Exception('offline');
      await pumpCard(tester, repository);

      expect(find.text('Saturday hike sign-up'), findsOneWidget);
      expect(
        find.text("Couldn't load this chain. Tap to try again."),
        findsOneWidget,
      );
      await tester.tap(
        find.text("Couldn't load this chain. Tap to try again."),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('0 joined'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('whole list', () {
    testWidgets('lists everyone, and lets members copy it', (tester) async {
      tallScreen(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repository = FakeChainRepository(
        description: 'Meet at the gate.',
        example: '1. Ada +1',
      );
      for (var i = 1; i <= 8; i++) {
        repository.add('u$i', 'Person $i', i == 2 ? 'vegan' : '');
      }
      await pumpCard(tester, repository);

      await tester.tap(find.byKey(const ValueKey('chain-card-chain-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chain-sheet')), findsOneWidget);
      expect(find.text('Started by Ada'), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('1. Ada +1'), findsOneWidget);
      expect(find.text('8.'), findsOneWidget);
      // Members cannot remove other lines or close the chain.
      expect(find.byTooltip("Remove Person 3's line"), findsNothing);
      expect(find.byKey(const ValueKey('chain-close-toggle')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chain-copy')));
      await tester.pumpAndSettle();
      expect(
        copied,
        startsWith('Saturday hike sign-up\n1. Person 1\n2. Person 2 vegan\n'),
      );
      expect(find.text('List copied.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the creator removes lines and closes and reopens', (
      tester,
    ) async {
      tallScreen(tester);
      final repository = FakeChainRepository(canManage: true)
        ..add('u1', 'Person 1')
        ..add('u2', 'Person 2');
      await pumpCard(tester, repository);
      await tester.tap(find.byKey(const ValueKey('chain-card-chain-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip("Remove Person 1's line"));
      await tester.pumpAndSettle();
      expect(repository.entries.map((e) => e.name), ['Person 2']);
      expect(find.byKey(const ValueKey('chain-line-entry-1')), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('chain-close-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('chain-close-toggle')));
      await tester.pumpAndSettle();
      expect(repository.closed, isTrue);
      expect(find.text('Reopen chain'), findsOneWidget);
      expect(
        find.text('This chain is closed. Nobody can join or change a line.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('chain-close-toggle')));
      await tester.pumpAndSettle();
      expect(repository.closed, isFalse);
      expect(find.text('Close chain'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('new chain', () {
    Future<void> open(
      WidgetTester tester,
      FakeChainRepository repository,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chainRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showChainCreateSheet(
                      context,
                      conversationId: 'conversation-1',
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('posts the title, description, example and cap', (
      tester,
    ) async {
      final repository = FakeChainRepository();
      await open(tester, repository);

      await tester.enterText(
        find.byKey(const ValueKey('chain-title-field')),
        '  Saturday hike sign-up ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chain-description-field')),
        'Meet at the gate at 8.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chain-example-field')),
        '1. Ada +1',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chain-max-field')),
        '12',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chain-post')));
      await tester.tap(find.byKey(const ValueKey('chain-post')));
      await tester.pumpAndSettle();

      final (conversation, draft) = repository.created.single;
      expect(conversation, 'conversation-1');
      expect(draft.title, 'Saturday hike sign-up');
      expect(draft.description, 'Meet at the gate at 8.');
      expect(draft.example, '1. Ada +1');
      expect(draft.maxEntries, 12);
      expect(draft.deadline, isNull);
      expect(find.text('New chain'), findsNothing, reason: 'the sheet closed');
    });

    testWidgets('needs a title and a sensible cap', (tester) async {
      final repository = FakeChainRepository();
      await open(tester, repository);

      await tester.ensureVisible(find.byKey(const ValueKey('chain-post')));
      await tester.tap(find.byKey(const ValueKey('chain-post')));
      await tester.pump();
      expect(find.text('Give the chain a title.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('chain-title-field')),
        'Lunch',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chain-max-field')),
        '0',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chain-post')));
      await tester.tap(find.byKey(const ValueKey('chain-post')));
      await tester.pump();
      expect(
        find.text('Max entries is a number from 1 to 500.'),
        findsOneWidget,
      );
      expect(repository.created, isEmpty);
    });

    testWidgets('a deadline from the quick picks goes with the chain', (
      tester,
    ) async {
      final repository = FakeChainRepository();
      await open(tester, repository);
      await tester.enterText(
        find.byKey(const ValueKey('chain-title-field')),
        'Lunch',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('chain-deadline-row')),
      );
      await tester.tap(find.byKey(const ValueKey('chain-deadline-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('when-tomorrowMorning')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chain-deadline-clear')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const ValueKey('chain-post')));
      await tester.tap(find.byKey(const ValueKey('chain-post')));
      await tester.pumpAndSettle();
      final deadline = repository.created.single.$2.deadline!;
      expect(deadline.hour, 9);
      expect(deadline.isAfter(DateTime.now()), isTrue);
    });
  });
}
