import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_repository.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../../mobile/phone_test_support.dart';
import 'agenda_fakes.dart';

void main() {
  Future<PhoneWorld> open(
    WidgetTester tester,
    FakeAgendaRepository agenda, {
    String location = '/agenda',
    PhoneViewport viewport = notchedPhone,
  }) async {
    usePhoneViewport(tester, viewport);
    final world = PhoneWorld()
      ..extraOverrides = agendaOverrides(agenda: agenda);
    await world.open(tester, location);
    await settle(tester);
    return world;
  }

  Color dangerText(WidgetTester tester, Finder at) =>
      tester.element(at).tokens.colors.dangerText;

  group('list view', () {
    testWidgets('groups the five sources by when, overdue first', (
      tester,
    ) async {
      final items = sampleAgenda();
      await open(tester, FakeAgendaRepository(items));

      expect(find.text('Agenda'), findsWidgets);
      for (final title in [
        'Send the trail permit form',
        'Bring the tripod',
        'Bouldering night',
        'Book the cabin',
        'Happy birthday, Grace!',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      // Overdue first, then Today, Tomorrow, and the later ones.
      final now = clock.now();
      final firstDay = weekdayFromFirstDayIndex(
        MaterialLocalizations.of(
          tester.element(find.byKey(const ValueKey('agenda-list'))),
        ).firstDayOfWeekIndex,
      );
      final expected = groupAgenda(items, now, firstDayOfWeek: firstDay).keys;
      expect(expected.first, AgendaBucket.overdue);
      // The ones in view have their section (the rest are below).
      for (final bucket in [
        AgendaBucket.overdue,
        AgendaBucket.today,
        AgendaBucket.tomorrow,
      ]) {
        expect(
          find.byKey(ValueKey('agenda-section-${bucket.name}')),
          findsOneWidget,
          reason: bucket.name,
        );
      }
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Needs you')).dy,
        lessThan(tester.getTopLeft(find.text('Today')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Today')).dy,
        lessThan(tester.getTopLeft(find.text('Tomorrow')).dy),
      );

      // The later ones are a scroll away.
      for (final title in ['Sunrise hike', 'Book club']) {
        await tester.scrollUntilVisible(
          find.text(title),
          200,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('agenda-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('what is overdue is red and counted', (tester) async {
      await open(tester, FakeAgendaRepository(sampleAgenda()));

      final header = find.text('Needs you');
      final style = tester.widget<Text>(header).style!;
      expect(style.color, dangerText(tester, header));
      // The count badge is the red one.
      expect(find.text('2'), findsWidgets);
      // The overdue row says so in words, not only in colour.
      final overdueRow = find.byKey(const ValueKey('agenda-task:task-overdue'));
      expect(
        find.descendant(of: overdueRow, matching: find.text('Overdue')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(overdueRow).label,
        matches('Task, Send the trail permit form, Overdue, .*'),
      );
      // An event today is not.
      final today = find.byKey(const ValueKey('agenda-chat_event:event-today'));
      expect(
        find.descendant(of: today, matching: find.text('Overdue')),
        findsNothing,
      );
      expect(
        find.descendant(of: today, matching: find.text('Going')),
        findsOneWidget,
      );
    });

    testWidgets('rows say what they are, when and where', (tester) async {
      await open(tester, FakeAgendaRepository(sampleAgenda()));

      final event = find.byKey(const ValueKey('agenda-chat_event:event-today'));
      expect(
        find.descendant(of: event, matching: find.textContaining('Event · ')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: event,
          matching: find.textContaining('Trail crew · The gym on 5th'),
        ),
        findsOneWidget,
      );
      final task = find.byKey(const ValueKey('agenda-task:task-today'));
      expect(
        find.descendant(of: task, matching: find.textContaining('All day')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey('agenda-scheduled_message:scheduled-tomorrow'),
          ),
          matching: find.textContaining('Scheduled message · '),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a reminder about a message that is gone says so', (
      tester,
    ) async {
      await open(
        tester,
        FakeAgendaRepository([
          agendaItem(
            AgendaKind.reminder,
            'gone',
            startsAt: agendaAt(
              dateOnly(clock.now()).add(const Duration(days: 2)),
              12,
            ),
            conversationId: 'dm-1',
            placeName: 'Bart the Bold',
          ),
          agendaItem(
            AgendaKind.reminder,
            'picture',
            startsAt: agendaAt(
              dateOnly(clock.now()).add(const Duration(days: 2)),
              13,
            ),
            conversationId: 'dm-1',
            meta: {'message_type': 'image'},
          ),
        ]),
      );
      expect(find.text('Message unavailable'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);
    });

    testWidgets('an empty agenda says so', (tester) async {
      await open(tester, FakeAgendaRepository());
      expect(find.byKey(const ValueKey('agenda-empty')), findsOneWidget);
      expect(find.text('Nothing on your agenda'), findsOneWidget);
    });

    testWidgets('a failure says so, and Refresh tries again', (tester) async {
      final repository = FakeAgendaRepository(sampleAgenda())
        ..failWith = Exception('offline');
      await open(tester, repository);
      expect(find.byKey(const ValueKey('agenda-error')), findsOneWidget);
      expect(find.text('Could not load your agenda.'), findsOneWidget);

      repository.failWith = null;
      await tester.tap(find.byKey(const ValueKey('agenda-refresh')));
      await settle(tester);
      expect(find.byKey(const ValueKey('agenda-error')), findsNothing);
      expect(find.text('Bouldering night'), findsOneWidget);
    });

    testWidgets('asks for two months back and three ahead', (tester) async {
      final repository = FakeAgendaRepository(sampleAgenda());
      await open(tester, repository);
      final request = repository.requests.first;
      final today = dateOnly(clock.now());
      expect(request.from, today.subtract(agendaLookBack));
      expect(request.to, today.add(agendaLookAhead));
    });
  });

  group('opening an entry', () {
    testWidgets('an event opens its chat', (tester) async {
      final world = await open(tester, FakeAgendaRepository(sampleAgenda()));
      await tester.tap(find.text('Bouldering night'));
      await settle(tester);
      expect(world.router.state.uri.path, '/chats/group-1');
    });

    testWidgets('a task opens its list at the task', (tester) async {
      final world = await open(tester, FakeAgendaRepository(sampleAgenda()));
      await tester.tap(find.text('Book the cabin'));
      await settle(tester);
      expect(world.router.state.uri.path, '/chats/group-1/workspace');
      expect(world.router.state.uri.queryParameters, {
        'tab': 'lists',
        'list': 'list-1',
        'item': 'task-today',
      });
    });

    testWidgets('a circle event opens the circle\'s events', (tester) async {
      final world = await open(tester, FakeAgendaRepository(sampleAgenda()));
      await tester.scrollUntilVisible(
        find.text('Sunrise hike'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('agenda-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Sunrise hike'));
      await settle(tester);
      expect(world.router.state.uri.path, '/circles/circle-1/events');
      expect(
        world.router.state.uri.queryParameters['event'],
        'circle-event-soon',
      );
    });

    testWidgets('a reminder opens its chat at the message', (tester) async {
      final world = await open(tester, FakeAgendaRepository(sampleAgenda()));
      await tester.tap(find.text('Bring the tripod'));
      await settle(tester);
      expect(world.router.state.uri.path, '/chats/dm-1');
    });

    testWidgets('a scheduled message opens its chat', (tester) async {
      final world = await open(tester, FakeAgendaRepository(sampleAgenda()));
      await tester.tap(find.text('Happy birthday, Grace!'));
      await settle(tester);
      expect(world.router.state.uri.path, '/chats/dm-2');
    });
  });

  group('month view', () {
    Future<PhoneWorld> openMonth(
      WidgetTester tester,
      FakeAgendaRepository repository,
    ) async {
      final world = await open(tester, repository);
      await tester.tap(find.byKey(const ValueKey('agenda-view-month')));
      await settle(tester);
      return world;
    }

    testWidgets('shows the month, today selected, with its entries', (
      tester,
    ) async {
      final repository = FakeAgendaRepository(sampleAgenda());
      await openMonth(tester, repository);

      final now = clock.now();
      final title = MaterialLocalizations.of(
        tester.element(find.byKey(const ValueKey('agenda-month-title'))),
      ).formatMonthYear(DateTime(now.year, now.month));
      expect(find.text(title), findsOneWidget);
      // A cell for the 15th of the month (always in the grid).
      expect(
        find.byKey(ValueKey('agenda-day-${now.year}-${now.month}-15')),
        findsOneWidget,
      );
      // Today's entries are listed below the grid.
      expect(find.byKey(const ValueKey('agenda-day-list')), findsOneWidget);
      expect(find.text('Bouldering night'), findsOneWidget);
      expect(find.text('Book the cabin'), findsOneWidget);
      expect(find.text('Happy birthday, Grace!'), findsNothing);
    });

    testWidgets('picking a day lists its entries; empty days say so', (
      tester,
    ) async {
      final repository = FakeAgendaRepository(sampleAgenda());
      await openMonth(tester, repository);
      final tomorrow = dateOnly(clock.now()).add(const Duration(days: 1));
      final next = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      // Tomorrow may be in next month's grid on the last day of a month.
      if (next.month != clock.now().month) {
        await tester.tap(find.byKey(const ValueKey('agenda-month-next')));
        await settle(tester);
      }
      await tester.tap(
        find.byKey(
          ValueKey('agenda-day-${next.year}-${next.month}-${next.day}'),
        ),
      );
      await settle(tester);
      expect(find.text('Happy birthday, Grace!'), findsOneWidget);
      expect(find.text('Bouldering night'), findsNothing);

      // A day with nothing on it.
      final quiet = DateTime(next.year, next.month, next.day + 10);
      if (quiet.month == next.month) {
        await tester.tap(
          find.byKey(
            ValueKey('agenda-day-${quiet.year}-${quiet.month}-${quiet.day}'),
          ),
        );
        await settle(tester);
        expect(find.byKey(const ValueKey('agenda-day-empty')), findsOneWidget);
        expect(find.text('Nothing planned'), findsOneWidget);
      }
    });

    testWidgets('next and previous change the month and fetch it', (
      tester,
    ) async {
      final repository = FakeAgendaRepository(sampleAgenda());
      await openMonth(tester, repository);
      final before = repository.requests.length;

      await tester.tap(find.byKey(const ValueKey('agenda-month-next')));
      await settle(tester);
      final now = clock.now();
      final next = DateTime(now.year, now.month + 1);
      expect(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byKey(const ValueKey('agenda-month-title'))),
          ).formatMonthYear(next),
        ),
        findsOneWidget,
      );
      expect(repository.requests.length, greaterThan(before));
      // The request covers the month and the days the grid borrows.
      final request = repository.requests.last;
      expect(request.from.isBefore(DateTime(next.year, next.month)), isTrue);
      expect(request.to.isAfter(DateTime(next.year, next.month + 1)), isTrue);

      await tester.tap(find.byKey(const ValueKey('agenda-month-previous')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('agenda-month-previous')));
      await settle(tester);
      expect(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byKey(const ValueKey('agenda-month-title'))),
          ).formatMonthYear(DateTime(now.year, now.month - 1)),
        ),
        findsOneWidget,
      );
      // Today is not in that month: a way back appears.
      await tester.tap(find.byKey(const ValueKey('agenda-month-today')));
      await settle(tester);
      expect(find.byKey(const ValueKey('agenda-month-today')), findsNothing);
    });

    testWidgets('a day cell reads as a date, its count and overdue', (
      tester,
    ) async {
      await openMonth(tester, FakeAgendaRepository(sampleAgenda()));
      final now = clock.now();
      final cell = find.byKey(
        ValueKey('agenda-day-${now.year}-${now.month}-${now.day}'),
      );
      final semantics = tester.getSemantics(cell);
      expect(semantics.label, contains('Today'));
      expect(semantics.label, contains('on the agenda'));
    });
  });

  group('entries', () {
    testWidgets('the phone home has an Agenda tile that opens it', (
      tester,
    ) async {
      final world = await open(
        tester,
        FakeAgendaRepository(sampleAgenda()),
        location: '/',
      );
      final tile = find.byKey(const ValueKey('phone-home-agenda'));
      expect(tile, findsOneWidget);
      expect(find.text('Agenda'), findsOneWidget);
      // Two things are overdue: the tile wears the red badge.
      expect(find.byKey(const ValueKey('phone-agenda-badge')), findsOneWidget);
      await tester.tap(tile);
      await settle(tester);
      expect(world.router.state.uri.path, '/agenda');
    });

    testWidgets('no badge when nothing is overdue', (tester) async {
      await open(
        tester,
        FakeAgendaRepository([
          agendaItem(
            AgendaKind.chatEvent,
            'e',
            startsAt: agendaAt(
              dateOnly(clock.now()).add(const Duration(days: 2)),
              12,
            ),
          ),
        ]),
        location: '/',
      );
      expect(find.byKey(const ValueKey('phone-home-agenda')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-agenda-badge')), findsNothing);
    });
  });
}
