import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/shared/models/circle_audit_entry.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/circle_role.dart';

import '../../mobile/phone_test_support.dart';

/// Circle events in the full app, with the phone fakes' circle.
void main() {
  void useWideScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> openEvents(WidgetTester tester, PhoneWorld world) async {
    await world.open(tester, '/circles/circle-1');
    await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
    await settle(tester);
  }

  testWidgets('the sidebar counts upcoming events and shows live ones', (
    tester,
  ) async {
    useWideScreen(tester);
    final world = PhoneWorld();
    await world.open(tester, '/circles/circle-1');

    final entry = find.byKey(const ValueKey('circle-events-entry'));
    expect(
      find.descendant(of: entry, matching: find.text('Events (3)')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('circle-events-live')), findsOneWidget);

    world.circles.events = [world.circles.events[1]];
    await world.close(tester);
    await world.open(tester, '/circles/circle-1');
    expect(find.text('Events (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('circle-events-live')), findsNothing);
    await world.close(tester);
  });

  testWidgets('events list in start order with interest toggles', (
    tester,
  ) async {
    final world = PhoneWorld();
    await openEvents(tester, world);

    expect(find.byKey(const ValueKey('circle-events-list')), findsOneWidget);
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget is Material &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('circle-event-'),
    );
    expect(
      [
        for (final element in cards.evaluate())
          ((element.widget.key! as ValueKey<String>).value),
      ],
      [
        'circle-event-event-live',
        'circle-event-event-hike',
        'circle-event-event-call',
      ],
    );
    expect(find.text('Live now'), findsOneWidget);
    expect(find.text('Mission Peak sunrise hike'), findsOneWidget);
    expect(
      find.text('14 interested · by Grace Brewster Murray Hopper'),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('circle-event-interest-event-hike')),
    );
    await settle(tester);
    expect(world.circles.eventCalls, ['interest event-hike']);
    expect(
      find.text('15 interested · by Grace Brewster Murray Hopper'),
      findsOneWidget,
    );

    // Cancelled events show only with past ones.
    expect(find.text('Bay Bridge night shoot'), findsNothing);
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('circle-events-show-past')),
    );
    await tester.tap(find.byKey(const ValueKey('circle-events-show-past')));
    await settle(tester);
    await scrollIntoView(tester, find.text('Bay Bridge night shoot'));
    expect(find.text('Cancelled'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('event detail with description, interested and calendar', (
    tester,
  ) async {
    final world = PhoneWorld();
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
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
    await openEvents(tester, world);
    await tester.tap(find.text('Golden hour photo walk along the Embarcadero'));
    await settle(tester);

    expect(find.byKey(const ValueKey('circle-event-detail')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('circle-event-description')),
      findsOneWidget,
    );
    expect(find.text('Created by Bart the Bold'), findsOneWidget);
    expect(find.text('#general'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('circle-event-add-to-calendar')),
    );
    await tester.tap(
      find.byKey(const ValueKey('circle-event-add-to-calendar')),
    );
    await settle(tester);
    expect(copied.single, startsWith('Golden hour photo walk'));
    expect(copied.single, contains('Where: #general'));
    expect(
      find.text('Event details copied. Paste them into your calendar.'),
      findsOneWidget,
    );
    await scrollIntoView(tester, find.text('Interested · 8'));
    await scrollIntoView(
      tester,
      find.byKey(const ValueKey('circle-event-interested-list')),
    );
    expect(find.text('Bart the Bold'), findsOneWidget);

    await world.close(tester);
  });

  testWidgets('managers create events and see validation', (tester) async {
    final world = PhoneWorld();
    await openEvents(tester, world);

    await tester.tap(find.byKey(const ValueKey('circle-events-create')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await settle(tester);
    expect(find.text('Give the event a title.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('event-title-field')),
      'Picnic',
    );
    await tester.tap(find.text('Elsewhere'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('event-save')));
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await settle(tester);
    expect(find.text('Say where the event takes place.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('event-location-field')),
      'Dolores Park',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('event-end-switch')));
    await tester.tap(find.byKey(const ValueKey('event-end-switch')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('event-save')));
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await settle(tester);

    final draft = world.circles.eventDrafts.last;
    expect(draft.eventId, isNull);
    expect(draft.title, 'Picnic');
    expect(draft.locationType, CircleEventLocationType.external);
    expect(draft.locationText, 'Dolores Park');
    expect(draft.channelId, isNull);
    expect(draft.endsAt!.difference(draft.startsAt), const Duration(hours: 1));
    expect(draft.startsAt.isAfter(DateTime.now()), isTrue);
    expect(find.text('Picnic'), findsOneWidget);
    await world.close(tester);
  });

  testWidgets('text channel events pick a channel', (tester) async {
    final world = PhoneWorld();
    await openEvents(tester, world);
    await tester.tap(find.byKey(const ValueKey('circle-events-create')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('event-title-field')),
      'Trivia night',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('event-save')));
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await settle(tester);

    final draft = world.circles.eventDrafts.last;
    expect(draft.locationType, CircleEventLocationType.text);
    expect(draft.channelId, 'ch-general');
    await world.close(tester);
  });

  testWidgets('managers edit and cancel events from the detail', (
    tester,
  ) async {
    final world = PhoneWorld();
    await openEvents(tester, world);
    await tester.tap(find.text('Mission Peak sunrise hike'));
    await settle(tester);

    await tester.tap(find.byTooltip('Event options'));
    await settle(tester);
    await tester.tap(find.text('Edit event'));
    await settle(tester);
    expect(find.text('Edit event'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('event-title-field')),
      'Mission Peak sunrise hike (rain date)',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('event-save')));
    await tester.tap(find.byKey(const ValueKey('event-save')));
    await settle(tester);
    expect(world.circles.eventDrafts.last.eventId, 'event-hike');
    expect(
      world.circles.eventDrafts.last.locationText,
      'Stanford Avenue Staging Area, Fremont, California',
    );
    expect(find.text('Mission Peak sunrise hike (rain date)'), findsOneWidget);

    await tester.tap(find.byTooltip('Event options'));
    await settle(tester);
    await tester.tap(find.text('Cancel event'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('circle-event-confirm-cancel')));
    await settle(tester);
    expect(world.circles.eventCalls, ['cancel event-hike']);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byTooltip('Event options'), findsNothing);
    await world.close(tester);
  });

  testWidgets('members without manage events cannot create them', (
    tester,
  ) async {
    final world = PhoneWorld();
    world.circles.detail = circleDetailWith(
      channelId: 'ch-general',
      permissions: CirclePermission.viewChannel.bit,
    );
    await openEvents(tester, world);
    expect(find.byKey(const ValueKey('circle-events-create')), findsNothing);
    await world.close(tester);
  });

  testWidgets('reminder links open the event', (tester) async {
    final world = PhoneWorld();
    await world.open(
      tester,
      CircleEventsScreen.pathFor('circle-1', eventId: 'event-hike'),
    );
    await settle(tester);
    expect(find.byKey(const ValueKey('circle-event-detail')), findsOneWidget);
    expect(find.text('Mission Peak sunrise hike'), findsOneWidget);
    await world.close(tester);
  });

  test('audit log describes event changes', () {
    CircleAuditEntry entry(String action, [Map<String, dynamic>? changes]) {
      return CircleAuditEntry(
        id: 'a',
        circleId: 'circle-1',
        action: action,
        targetType: 'event',
        targetLabel: 'Hike',
        changes: changes ?? const {},
        createdAt: DateTime.utc(2026, 10, 14),
        actor: const CircleAuditActor(
          id: 'user-1',
          username: 'ada',
          displayName: 'Ada',
        ),
      );
    }

    expect(
      circleAuditSummary(entry('event_create'), null).toPlainText(),
      'Ada scheduled event Hike',
    );
    expect(
      circleAuditSummary(
        entry('event_update', {
          'title': {'old': 'Walk', 'new': 'Hike'},
        }),
        null,
      ).toPlainText(),
      'Ada renamed event Walk to Hike',
    );
    expect(
      circleAuditSummary(entry('event_cancel'), null).toPlainText(),
      'Ada cancelled event Hike',
    );
    expect(circleAuditIcon('event_cancel'), Icons.event_busy_outlined);
    expect(
      CircleAuditActionGroup.of('event_update'),
      CircleAuditActionGroup.event,
    );
    final details = circleAuditDetails(
      entry('event_update', {
        'starts_at': {
          'old': '2026-10-20T15:00:00Z',
          'new': '2026-10-21T15:00:00Z',
        },
      }),
    );
    expect(details.single.label, 'Starts');
    expect(details.single.value, contains('→'));
  });

  test('calendar files escape text and use UTC', () {
    final event = CircleEvent(
      id: 'event-1',
      circleId: 'circle-1',
      title: 'Hike, then lunch; maybe',
      locationType: CircleEventLocationType.external,
      locationText: 'Trailhead',
      startsAt: DateTime.utc(2026, 10, 20, 15),
    );
    final file = circleEventCalendarFile(
      event,
      now: DateTime.utc(2026, 10, 14, 9),
    );
    expect(file, contains('DTSTART:20261020T150000Z'));
    expect(file, contains('DTEND:20261020T170000Z'));
    expect(file, contains(r'SUMMARY:Hike\, then lunch\; maybe'));
    expect(file, contains('\r\n'));
  });
}
