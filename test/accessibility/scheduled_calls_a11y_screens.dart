// Scheduled calls (E2), for the accessibility guard (guidelines_test.dart) and
// the screenshot tools: an event card with its green "In progress · Join" and
// the "Join the call" of the minutes before, the event sheet with the same,
// the pinned strip with its short "Join", the event form with the "Attach a
// call" row (editing one, and a new "Schedule a call"), and an agenda row for
// a call, at large text, narrow and with Care mode on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_row.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/event_extras.dart';

import '../features/events2/events2_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

const _callExtras = EventExtras(
  callLinkCode: 'abcdefghjk23',
  capacity: 8,
  recurrence: EventRecurrence.weekly,
  recurrenceTimeZone: 'Pacific/Auckland',
  seriesId: 's-1',
);

/// A call that started [startedAgo] ago, or starts in [startsIn].
ChatEvent _callEvent({
  Duration startedAgo = Duration.zero,
  Duration startsIn = Duration.zero,
  EventExtras extras = _callExtras,
  bool pinned = false,
}) {
  final base = chatEventWith(extras: extras, myStatus: ChatEventRsvp.going);
  return ChatEvent(
    id: base.id,
    conversationId: base.conversationId,
    title: 'Thursday evening design review with the whole team',
    startsAt: DateTime.now().add(startsIn).subtract(startedAgo),
    locationText: 'Voice call',
    createdBy: base.createdBy,
    creatorName: base.creatorName,
    goingCount: base.goingCount,
    maybeCount: base.maybeCount,
    myStatus: base.myStatus,
    canManage: true,
    pinnedAt: pinned ? DateTime.now() : null,
    attendees: base.attendees,
    extras: extras,
  );
}

const _live = Duration(minutes: 35);
const _soon = Duration(minutes: 8);

void _fakes(PhoneWorld world, ChatEvent event) {
  world.extraOverrides = [
    ...world.extraOverrides,
    events2RepositoryProvider.overrideWithValue(FakeEvents2Repository()),
    chatEventsRepositoryProvider.overrideWithValue(
      FakeEventsChatRepository([event]),
    ),
    timeTokenFollowsClockProvider.overrideWithValue(false),
  ];
}

Future<void> _card(
  WidgetTester tester,
  PhoneWorld world,
  ChatEvent event,
) async {
  _fakes(world, event);
  await pumpStandalone(
    tester,
    world,
    const Scaffold(
      body: SingleChildScrollView(
        child: ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
      ),
    ),
  );
}

Future<void> _sheet(
  WidgetTester tester,
  PhoneWorld world,
  ChatEvent event,
) async {
  _fakes(world, event);
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(showChatEventSheet(context, 'e-1', eventsConversationId));
  await settle(tester);
}

Future<void> _strip(
  WidgetTester tester,
  PhoneWorld world,
  ChatEvent event,
) async {
  _fakes(world, event);
  await pumpStandalone(
    tester,
    world,
    const Scaffold(
      body: Column(
        children: [ChatEventStrip(conversationId: eventsConversationId)],
      ),
    ),
  );
}

Future<void> _editor(
  WidgetTester tester,
  PhoneWorld world, {
  required bool scheduleCall,
}) async {
  final event = _callEvent(startsIn: const Duration(days: 2));
  _fakes(world, event);
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    showChatEventEditor(
      context,
      conversationId: eventsConversationId,
      event: scheduleCall ? null : event,
      scheduleCall: scheduleCall,
    ),
  );
  await settle(tester);
  // The form is a long list: go to the end, where the rows of More options are.
  final position = tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ChatEventEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;
  position.jumpTo(position.maxScrollExtent);
  await settle(tester);
  await tester.ensureVisible(find.byKey(const ValueKey('event-option-call')));
  await settle(tester);
}

Future<void> _agenda(WidgetTester tester, PhoneWorld world) async {
  AgendaItem item(Map<String, dynamic> meta, String title) =>
      AgendaItem.tryParse({
        'kind': 'chat_event',
        'title': title,
        'starts_at': DateTime.now()
            .add(const Duration(hours: 5))
            .toUtc()
            .toIso8601String(),
        'ends_at': DateTime.now()
            .add(const Duration(hours: 6))
            .toUtc()
            .toIso8601String(),
        'all_day': false,
        'conversation_id': 'conv-1',
        'target_id': title,
        'place_name': 'Hike crew',
        'meta': meta,
      })!;
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Column(
        children: [
          AgendaRow(
            item: item({
              'status': 'going',
              'call_link_code': 'abcdefghjk23',
            }, 'Thursday sync'),
            now: DateTime.now(),
            onPressed: () {},
          ),
          AgendaRow(
            item: item({'status': 'going'}, 'Climbing night'),
            now: DateTime.now(),
            onPressed: () {},
          ),
        ],
      ),
    ),
  );
}

final scheduledCallsA11yScreens = <A11yScreen>[
  A11yScreen(
    'scheduled-call-card-live',
    (tester, world) => _card(tester, world, _callEvent(startedAgo: _live)),
  ),
  A11yScreen(
    'scheduled-call-card-live-large-text',
    (tester, world) => _card(tester, world, _callEvent(startedAgo: _live)),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'scheduled-call-card-live-narrow',
    (tester, world) => _card(tester, world, _callEvent(startedAgo: _live)),
    viewport: smallPhone,
  ),
  A11yScreen('scheduled-call-card-live-care-mode', (tester, world) async {
    _care(world);
    await _card(tester, world, _callEvent(startedAgo: _live));
  }),
  A11yScreen(
    'scheduled-call-card-soon',
    (tester, world) => _card(tester, world, _callEvent(startsIn: _soon)),
  ),
  A11yScreen(
    'scheduled-call-card-later',
    (tester, world) =>
        _card(tester, world, _callEvent(startsIn: const Duration(days: 2))),
  ),
  A11yScreen(
    'scheduled-call-sheet-live',
    (tester, world) => _sheet(tester, world, _callEvent(startedAgo: _live)),
  ),
  A11yScreen(
    'scheduled-call-sheet-live-large-text',
    (tester, world) => _sheet(tester, world, _callEvent(startedAgo: _live)),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'scheduled-call-sheet-live-narrow',
    (tester, world) => _sheet(tester, world, _callEvent(startedAgo: _live)),
    viewport: smallPhone,
  ),
  A11yScreen(
    'scheduled-call-strip-live',
    (tester, world) =>
        _strip(tester, world, _callEvent(startedAgo: _live, pinned: true)),
  ),
  A11yScreen(
    'scheduled-call-strip-live-large-text',
    (tester, world) =>
        _strip(tester, world, _callEvent(startedAgo: _live, pinned: true)),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'scheduled-call-strip-live-narrow',
    (tester, world) =>
        _strip(tester, world, _callEvent(startedAgo: _live, pinned: true)),
    viewport: smallPhone,
  ),
  A11yScreen(
    'scheduled-call-editor',
    (tester, world) => _editor(tester, world, scheduleCall: false),
  ),
  A11yScreen(
    'scheduled-call-editor-large-text',
    (tester, world) => _editor(tester, world, scheduleCall: false),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'scheduled-call-editor-narrow',
    (tester, world) => _editor(tester, world, scheduleCall: false),
    viewport: smallPhone,
  ),
  A11yScreen(
    'scheduled-call-editor-new',
    (tester, world) => _editor(tester, world, scheduleCall: true),
  ),
  A11yScreen('scheduled-call-agenda', _agenda),
  A11yScreen('scheduled-call-agenda-narrow', _agenda, viewport: smallPhone),
];
