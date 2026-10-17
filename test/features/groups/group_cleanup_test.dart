import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/groups/group_cleanup.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

InactiveGroup quietGroup(
  String id, {
  String? title,
  int days = 100,
  int members = 5,
  bool canLeave = true,
  bool pinned = false,
}) {
  return InactiveGroup(
    id: id,
    title: title ?? 'Group $id',
    memberCount: members,
    lastActivityAt: DateTime.now().subtract(Duration(days: days)),
    canLeave: canLeave,
    isPinned: pinned,
  );
}

class _FakeCleanupRepository implements GroupCleanupRepository {
  _FakeCleanupRepository(this.byDays);

  final Map<int, List<InactiveGroup>> byDays;
  final asked = <int>[];

  @override
  Future<List<InactiveGroup>> listInactiveGroups(int days) async {
    asked.add(days);
    return byDays[days] ?? const [];
  }
}

class _LeavingRepository implements ChatsRepository {
  final left = <String>[];
  final failing = <String>{};

  @override
  Future<void> leaveGroupConversation(String conversationId) async {
    if (failing.contains(conversationId)) {
      throw StateError('Sole owner cannot leave');
    }
    left.add(conversationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('model', () {
    test('reads the server row', () {
      final parsed = InactiveGroup.fromJson({
        'conversation_id': 'c-1',
        'title': '  ',
        'avatar_url': null,
        'member_count': 12,
        'last_activity_at': '2026-04-01T10:00:00+00:00',
        'my_role': 'owner',
        'can_leave': false,
        'is_pinned': true,
        'is_muted': false,
      });
      expect(parsed.id, 'c-1');
      expect(parsed.name, 'Untitled group');
      expect(parsed.memberCount, 12);
      expect(parsed.canLeave, isFalse);
      expect(parsed.isPinned, isTrue);
      expect(InactivityPeriod.values.map((p) => p.days), [30, 90, 180]);
    });
  });

  group('controller', () {
    ProviderContainer containerWith(_LeavingRepository leaving) {
      final container = ProviderContainer(
        overrides: [chatsRepositoryProvider.overrideWithValue(leaving)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('leaves the groups once the undo window has passed', () async {
      final leaving = _LeavingRepository();
      final container = containerWith(leaving);
      final controller = container.read(
        groupCleanupControllerProvider.notifier,
      );
      GroupCleanupResult? result;
      controller.schedule(
        [quietGroup('a'), quietGroup('b')],
        delay: const Duration(milliseconds: 30),
        onFinished: (value) => result = value,
      );
      expect(container.read(groupCleanupControllerProvider), hasLength(2));
      expect(leaving.left, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(leaving.left, ['a', 'b']);
      expect(result!.left.map((g) => g.id), ['a', 'b']);
      expect(result!.failed, isEmpty);
      expect(container.read(groupCleanupControllerProvider), isEmpty);
    });

    test('undo within the window leaves nothing', () async {
      final leaving = _LeavingRepository();
      final container = containerWith(leaving);
      final controller = container.read(
        groupCleanupControllerProvider.notifier,
      );
      var finished = false;
      controller.schedule(
        [quietGroup('a')],
        delay: const Duration(milliseconds: 30),
        onFinished: (_) => finished = true,
      );
      expect(controller.undo(), isTrue);
      expect(controller.undo(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(leaving.left, isEmpty);
      expect(finished, isFalse);
      expect(container.read(groupCleanupControllerProvider), isEmpty);
    });

    test('a group that cannot be left does not stop the others', () async {
      final leaving = _LeavingRepository()..failing.add('b');
      final container = containerWith(leaving);
      GroupCleanupResult? result;
      container
          .read(groupCleanupControllerProvider.notifier)
          .schedule(
            [quietGroup('a'), quietGroup('b'), quietGroup('c')],
            delay: const Duration(milliseconds: 10),
            onFinished: (value) => result = value,
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(leaving.left, ['a', 'c']);
      expect(result!.failed.map((g) => g.id), ['b']);
    });

    test('a second batch waits for the first', () {
      final leaving = _LeavingRepository();
      final container = containerWith(leaving);
      final controller = container.read(
        groupCleanupControllerProvider.notifier,
      );
      controller.schedule(
        [quietGroup('a')],
        delay: const Duration(seconds: 30),
        onFinished: (_) {},
      );
      controller.schedule(
        [quietGroup('z')],
        delay: const Duration(seconds: 30),
        onFinished: (_) {},
      );
      expect(container.read(groupCleanupControllerProvider).map((g) => g.id), [
        'a',
      ]);
      controller.undo();
    });
  });

  group('screen', () {
    late _FakeCleanupRepository cleanup;
    late _LeavingRepository leaving;

    Future<void> openScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      cleanup = _FakeCleanupRepository({
        30: [
          quietGroup('f', title: 'Forty days', days: 40),
          quietGroup('h', title: 'Hundred days', days: 100),
          quietGroup('y', title: 'Year old', days: 365, pinned: true),
          quietGroup(
            'o',
            title: 'Mine to hand over',
            days: 200,
            canLeave: false,
          ),
        ],
        90: [
          quietGroup('h', title: 'Hundred days', days: 100),
          quietGroup('y', title: 'Year old', days: 365, pinned: true),
          quietGroup(
            'o',
            title: 'Mine to hand over',
            days: 200,
            canLeave: false,
          ),
        ],
        180: [quietGroup('y', title: 'Year old', days: 365, pinned: true)],
      });
      leaving = _LeavingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupCleanupRepositoryProvider.overrideWithValue(cleanup),
            chatsRepositoryProvider.overrideWithValue(leaving),
          ],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const GroupCleanupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists groups quiet for 90 days and switches period', (
      tester,
    ) async {
      await openScreen(tester);
      expect(cleanup.asked, [90]);
      expect(find.byKey(const ValueKey('group-cleanup-row-h')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-cleanup-row-f')), findsNothing);
      expect(find.textContaining('Last activity 3 months ago'), findsOneWidget);
      expect(find.text('Year old'), findsOneWidget);
      expect(find.textContaining('Last activity 1 year ago'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-cleanup-30')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-cleanup-row-f')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-cleanup-180')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-cleanup-row-h')), findsNothing);
      expect(find.byKey(const ValueKey('group-cleanup-row-y')), findsOneWidget);
    });

    testWidgets('select all skips groups that cannot be left', (tester) async {
      await openScreen(tester);
      expect(find.text('2 quiet groups'), findsOneWidget);
      expect(
        find.text('You are the only owner. Hand it over first.'),
        findsWidgets,
      );

      await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
      await tester.pump();
      expect(find.text('2 of 2 selected'), findsOneWidget);
      expect(find.text('Leave 2'), findsOneWidget);

      // A locked group does not toggle.
      await tester.tap(find.byKey(const ValueKey('group-cleanup-row-o')));
      await tester.pump();
      expect(find.text('2 of 2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-cleanup-row-h')));
      await tester.pump();
      expect(find.text('1 of 2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
      await tester.pump();
      expect(find.text('2 of 2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
      await tester.pump();
      expect(find.text('2 quiet groups'), findsOneWidget);
    });

    testWidgets('Leave is off until something is selected', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byKey(const ValueKey('group-cleanup-leave')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('asks, then waits for undo before leaving', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byKey(const ValueKey('group-cleanup-select-all')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-cleanup-leave')));
      await tester.pumpAndSettle();
      expect(find.text('Leave 2 groups?'), findsOneWidget);

      // Cancelling leaves everything as it was.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(leaving.left, isEmpty);
      expect(find.text('2 of 2 selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-cleanup-leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-cleanup-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Leaving 2 groups…'), findsOneWidget);
      expect(leaving.left, isEmpty);
      // The groups drop off the list while they wait.
      expect(find.byKey(const ValueKey('group-cleanup-row-h')), findsNothing);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Nothing changed. You are still in them.'),
        findsOneWidget,
      );
      await tester.pump(GroupCleanupController.undoWindow);
      expect(leaving.left, isEmpty);
      expect(find.byKey(const ValueKey('group-cleanup-row-h')), findsOneWidget);
    });

    testWidgets('leaves the groups when the window passes', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byKey(const ValueKey('group-cleanup-row-h')));
      await tester.tap(find.byKey(const ValueKey('group-cleanup-row-y')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-cleanup-leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-cleanup-confirm')));
      await tester.pump();
      await tester.pump(GroupCleanupController.undoWindow);
      await tester.pump(const Duration(milliseconds: 400));
      expect(leaving.left, ['h', 'y']);
      expect(find.text('Left 2 groups.'), findsOneWidget);
      // Let the result snackbar go.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('says so when nothing has been quiet that long', (
      tester,
    ) async {
      await openScreen(tester);
      cleanup.byDays[90] = [];
      await tester.tap(find.byKey(const ValueKey('group-cleanup-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-cleanup-90')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-cleanup-empty')), findsOneWidget);
      expect(find.text('Nothing to clean up'), findsOneWidget);
    });
  });
}
