import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/edit_history/edit_history_chat.dart';
import 'package:wecord/features/chats/edit_history/edit_history_sheet.dart';
import 'package:wecord/features/chats/edit_history/edit_version.dart';
import 'package:wecord/features/chats/thread/footer_widgets.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/bubble_footer_builtin.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/features/chats/thread/registry/message_actions_registrations.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../../mobile/phone_test_support.dart';
import 'edit_history_fakes.dart';

final _sent = DateTime(2026, 10, 18, 9, 0);
final _firstEdit = DateTime(2026, 10, 18, 9, 5);
final _secondEdit = DateTime(2026, 10, 18, 9, 20);

ChatMessage _edited({String id = 'm1', DateTime? recalledAt}) => ChatMessage(
  id: id,
  conversationId: 'c1',
  senderId: 'u1',
  type: MessageType.text,
  body: 'Lunch at 1pm',
  createdAt: _sent,
  editedAt: _secondEdit,
  recalledAt: recalledAt,
);

FakeEditHistoryRepository _history() => FakeEditHistoryRepository({
  'm1': [
    editVersion(2, 'Lunch at noon', _firstEdit),
    editVersion(1, 'Lunch today?', _sent),
  ],
});

Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: WeCordTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('MessageEditVersion', () {
    test('reads a row of message_edits', () {
      final version = MessageEditVersion.fromJson({
        'version': 2,
        'body': 'Hi @Eve',
        'mentions': [
          {
            'kind': 'user',
            'user_id': 'u2',
            'display_name': 'Eve',
            'start': 3,
            'end': 7,
          },
        ],
        'edited_at': '2026-10-18T09:05:00Z',
      });
      expect(version.version, 2);
      expect(version.body, 'Hi @Eve');
      expect(version.mentions.single.displayName, 'Eve');
      expect(
        version.editedAt.isAtSameMomentAs(DateTime.utc(2026, 10, 18, 9, 5)),
        isTrue,
      );
      expect(version.isOriginal, isFalse);
      expect(
        MessageEditVersion.fromJson({
          'version': 1,
          'body': 'x',
          'edited_at': '2026-10-18T09:00:00Z',
        }).isOriginal,
        isTrue,
      );
    });
  });

  group('the edited mark', () {
    testWidgets('is plain text without a tap handler', (tester) async {
      await tester.pumpWidget(_host(const EditedMarker(color: Colors.grey)));
      expect(find.text('edited'), findsOneWidget);
      expect(find.byKey(const ValueKey('edited-marker')), findsNothing);
    });

    testWidgets('is a button that reads "Edited, double tap to see history"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _host(EditedMarker(color: Colors.grey, onTap: () => taps += 1)),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel('Edited, double tap to see history'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.text('edited'));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('only an edited message that is still there opens history', (
      tester,
    ) async {
      expect(hasEditHistory(_edited()), isTrue);
      expect(hasEditHistory(_edited(recalledAt: _sent)), isFalse);
      expect(
        hasEditHistory(
          ChatMessage(
            id: 'm2',
            conversationId: 'c1',
            senderId: 'u1',
            type: MessageType.text,
            body: 'x',
            createdAt: _sent,
          ),
        ),
        isFalse,
      );
    });
  });

  group('the history sheet', () {
    Future<void> open(
      WidgetTester tester,
      FakeEditHistoryRepository repository, {
      ChatMessage? message,
    }) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditHistory(context, message ?? _edited()),
              child: const Text('open'),
            ),
          ),
          overrides: [editHistoryOverride(repository)],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the versions newest first with their times', (
      tester,
    ) async {
      final repository = _history();
      await open(tester, repository);

      expect(find.text('Edit history'), findsOneWidget);
      expect(repository.reads, ['m1']);
      final current = tester.getTopLeft(find.text('Lunch at 1pm')).dy;
      final second = tester.getTopLeft(find.text('Lunch at noon')).dy;
      final first = tester.getTopLeft(find.text('Lunch today?')).dy;
      expect(current, lessThan(second));
      expect(second, lessThan(first));

      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.textContaining('09:20'), findsOneWidget);
      expect(find.textContaining('09:05'), findsOneWidget);
      expect(find.textContaining('09:00'), findsOneWidget);
    });

    testWidgets('shows the current text alone when nothing was kept', (
      tester,
    ) async {
      await open(tester, FakeEditHistoryRepository());
      expect(find.text('Lunch at 1pm'), findsOneWidget);
      expect(
        find.text('No earlier versions were saved for this message.'),
        findsOneWidget,
      );
    });

    testWidgets('says so when it cannot load, and retries', (tester) async {
      final repository = _history()..failures = 1;
      await open(tester, repository);
      expect(find.text('Could not load the edit history.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edit-history-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Lunch today?'), findsOneWidget);
      expect(repository.reads, ['m1', 'm1']);
    });

    testWidgets('each version reads as one line for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, _history());
      final node = tester.getSemantics(
        find.byKey(const ValueKey('edit-version-1')),
      );
      expect(node.label, contains('Original'));
      expect(node.label, contains('Lunch today?'));
      handle.dispose();
    });
  });

  group('in the chat', () {
    testWidgets('tapping Edited on a message opens its history', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final world = PhoneWorld();
      world.chats.messages = [
        phoneMessage(
          'm1',
          bart,
          'Lunch at 1pm',
          minutesAgo: 30,
          editedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        phoneMessage('m2', bart, 'Never changed', minutesAgo: 20),
      ];
      world.extraOverrides = [editHistoryOverride(_history())];
      await world.open(
        tester,
        '${ChatsScreen.path}/dm-1',
        extra: ChatThreadRouteExtra(
          title: bart.displayName,
          type: ConversationType.direct,
        ),
      );

      // Only the edited message has the mark.
      expect(find.byKey(const ValueKey('edited-marker')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('edited-marker')));
      await settle(tester);

      expect(find.text('Edit history'), findsOneWidget);
      expect(find.text('Lunch today?'), findsOneWidget);
      expect(find.text('Lunch at noon'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      await world.close(tester);
    });

    testWidgets('the message menu has Edit history for an edited message', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        usePhoneViewport(
          tester,
          const PhoneViewport(
            name: 'desktop',
            size: Size(1440, 900),
            devicePixelRatio: 1,
          ),
        );
        final world = PhoneWorld();
        world.chats.messages = [
          phoneMessage(
            'm1',
            bart,
            'Lunch at 1pm',
            minutesAgo: 30,
            editedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
          phoneMessage('m2', bart, 'Never changed', minutesAgo: 20),
        ];
        world.extraOverrides = [editHistoryOverride(_history())];
        await world.open(
          tester,
          '${ChatsScreen.path}/dm-1',
          extra: ChatThreadRouteExtra(
            title: bart.displayName,
            type: ConversationType.direct,
          ),
        );

        await tester.tap(find.text('Never changed'), buttons: kSecondaryButton);
        await settle(tester);
        expect(find.text('Edit history'), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);

        await tester.tap(find.text('Lunch at 1pm'), buttons: kSecondaryButton);
        await settle(tester);
        expect(find.text('Edit history'), findsOneWidget);
        // Between Edit (600) and Create task (700).
        final forward = tester.getCenter(find.text('Forward')).dy;
        final history = tester.getCenter(find.text('Edit history')).dy;
        final task = tester.getCenter(find.text('Create task')).dy;
        expect(forward, lessThan(history));
        expect(history, lessThan(task));

        await tester.tap(find.text('Edit history'));
        await settle(tester);
        expect(find.text('Lunch today?'), findsOneWidget);
        await world.close(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  test('the registrations keep the built-in entry and add the menu action', () {
    expect(
      BubbleFooterRegistry(builtInBubbleFooterEntries).ids,
      contains('edited'),
    );
    expect(
      MessageActionRegistry([...messageActionExtensions]).ids,
      contains('edit-history'),
    );
  });
}
