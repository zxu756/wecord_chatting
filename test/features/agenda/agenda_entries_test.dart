import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/shell/quick_switcher.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../accessibility/a11y_screens.dart' show desktopViewport;
import '../../mobile/phone_test_support.dart';
import 'agenda_fakes.dart';

void main() {
  group('quick switcher shortcut', () {
    test('answers a query that starts the word', () {
      for (final query in ['ag', 'agen', 'Agenda', '  AGENDA ']) {
        final item = agendaQuickSwitchItem(query);
        expect(item, isNotNull, reason: query);
        expect(item!.kind, QuickSwitchKind.agenda);
        expect(item.title, 'Agenda');
      }
    });

    test('stays out of the way of everything else', () {
      for (final query in [
        '',
        ' ',
        'a',
        'g',
        'enda',
        'gen',
        '@ag',
        '#ag',
        '*ag',
        'xyz',
      ]) {
        expect(agendaQuickSwitchItem(query), isNull, reason: query);
      }
    });
  });

  group('entries', () {
    testWidgets('the desktop sidebar has an Agenda row after Saved', (
      tester,
    ) async {
      usePhoneViewport(tester, desktopViewport);
      final world = PhoneWorld()
        ..extraOverrides = agendaOverrides(
          agenda: FakeAgendaRepository(sampleAgenda()),
        );
      await world.open(tester, '/');
      await settle(tester);

      final row = find.byKey(const ValueKey('home-agenda'));
      expect(row, findsOneWidget);
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('home-saved'))).dy,
        ),
      );
      // Two overdue entries: the row wears the red count.
      expect(
        find.descendant(of: row, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(row);
      await settle(tester);
      expect(world.router.state.uri.path, '/agenda');
      // The sidebar stays, with Agenda selected, beside the page.
      expect(find.byKey(const ValueKey('home-agenda')), findsOneWidget);
      expect(find.byKey(const ValueKey('agenda-list')), findsOneWidget);
      expect(find.text('Bouldering night'), findsOneWidget);
    });

    testWidgets('the quick switcher finds Agenda and opens it', (tester) async {
      usePhoneViewport(tester, desktopViewport);
      final world = PhoneWorld()
        ..extraOverrides = agendaOverrides(agenda: FakeAgendaRepository());
      await world.open(tester, '/');
      await settle(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await settle(tester);
      if (find.byKey(const ValueKey('quick-switcher')).evaluate().isEmpty) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await settle(tester);
      }
      expect(find.byKey(const ValueKey('quick-switcher')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('quick-switcher-field')),
        'agen',
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('quick-switch-agenda')), findsOneWidget);
      expect(find.text('Events, tasks and reminders'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(world.router.state.uri.path, '/agenda');
    });

    testWidgets('the shortcut leads the places that match', (tester) async {
      QuickSwitchItem? picked;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            conversationsProvider.overrideWith(
              (ref) async => const [
                ConversationSummary(
                  id: 'g-agenda',
                  type: ConversationType.group,
                  unreadCount: 0,
                  title: 'Agenda planning',
                ),
              ],
            ),
            circleSummariesProvider.overrideWith(
              (ref) async => const <CircleSummary>[],
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDialog<QuickSwitchItem>(
                    context: context,
                    builder: (context) => const QuickSwitcherDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quick-switcher-field')),
        'agenda',
      );
      await tester.pump();
      expect(find.text('Agenda planning'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked?.kind, QuickSwitchKind.agenda);
    });
  });
}
