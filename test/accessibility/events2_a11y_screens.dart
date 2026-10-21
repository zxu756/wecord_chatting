// Events 2.0 (C10), for the accessibility guard (guidelines_test.dart) and the
// screenshot tools: an event card with its cover, repeat and seats, the event
// sheet (check-in, pictures, organiser's list), the event form with its new
// rows, the questions editor, the sign-up questions, the organiser's list, the
// check-in code and the page of a check-in link, and the circle's events with
// the same, at large text, narrow and with Care mode on.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/events2/event_check_in.dart';
import 'package:wecord/features/events2/event_manage_sheet.dart';
import 'package:wecord/features/events2/event_options_section.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/ui/ui.dart';

import '../features/events2/events2_fakes.dart';
import '../mobile/phone_test_support.dart';
import 'a11y_screens.dart';

void _care(PhoneWorld world) {
  world.careStore.initial = const CareModeSettings(enabled: true);
}

const _busyExtras = EventExtras(
  coverPath: 'conv-1/events/cover.jpg',
  recurrence: EventRecurrence.weekly,
  recurrenceTimeZone: 'Pacific/Auckland',
  seriesId: 's-1',
  questions: picnicQuestions,
  capacity: 3,
  waitlistCount: 2,
  checkedInCount: 1,
  photoCount: 2,
);

/// An event that is about to start, so check-in and pictures show.
ChatEvent _soonEvent({
  EventExtras extras = _busyExtras,
  ChatEventRsvp? myStatus,
}) => chatEventWith(
  extras: extras,
  startsAt: DateTime.now().add(const Duration(minutes: 40)),
  myStatus: myStatus,
);

FakeEvents2Repository _fakes(
  PhoneWorld world, {
  List<ChatEvent>? events,
  List<EventPhoto> photos = const [],
}) {
  final events2 = FakeEvents2Repository()..photos = photos;
  world.extraOverrides = [
    ...world.extraOverrides,
    events2RepositoryProvider.overrideWithValue(events2),
    chatEventsRepositoryProvider.overrideWithValue(
      FakeEventsChatRepository(events ?? [_soonEvent()]),
    ),
    timeTokenFollowsClockProvider.overrideWithValue(false),
  ];
  return events2;
}

const _photos = [
  EventPhoto(
    id: 'p1',
    bucket: 'chat-images',
    path: 'conv-1/events/a.jpg',
    userId: 'user-2',
    uploaderName: 'Bart',
    canDelete: true,
  ),
  EventPhoto(
    id: 'p2',
    bucket: 'chat-images',
    path: 'conv-1/events/b.jpg',
    userId: 'user-1',
    uploaderName: 'Ada',
    mine: true,
    canDelete: true,
  ),
  EventPhoto(
    id: 'p3',
    bucket: 'chat-images',
    path: 'conv-1/events/c.jpg',
    userId: 'user-3',
    uploaderName: 'Grace',
  ),
];

/// The themed app with a button's worth of nothing, then [open] on its
/// context.
Future<void> _inApp(
  WidgetTester tester,
  PhoneWorld world,
  Widget Function(BuildContext context) open,
) async {
  await pumpStandalone(
    tester,
    world,
    Scaffold(body: Builder(builder: (context) => open(context))),
  );
}

Future<void> _chatCard(
  WidgetTester tester,
  PhoneWorld world, {
  EventExtras extras = _busyExtras,
}) async {
  _fakes(world, events: [_soonEvent(extras: extras)]);
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

Future<void> _chatSheet(
  WidgetTester tester,
  PhoneWorld world, {
  ChatEventRsvp? myStatus,
  EventExtras extras = _busyExtras,
}) async {
  _fakes(
    world,
    events: [_soonEvent(extras: extras, myStatus: myStatus)],
    photos: _photos,
  );
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(showChatEventSheet(context, 'e-1', eventsConversationId));
  await settle(tester);
}

Future<void> _chatEditor(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await pumpStandalone(tester, world, const Scaffold(body: SizedBox.expand()));
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    showChatEventEditor(
      context,
      conversationId: eventsConversationId,
      event: _soonEvent(),
    ),
  );
  await settle(tester);
  // The form is a long list: go to the end, where the new rows are.
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
  await tester.ensureVisible(
    find.byKey(const ValueKey('event-option-capacity')),
  );
  await settle(tester);
}

Future<void> _questionsEditor(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await pumpStandalone(
    tester,
    world,
    Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showWeCordSheet<void>(
              context,
              title: tr('Questions'),
              detents: const [0.92],
              builder: (context, controller) => EventQuestionsEditor(
                initial: picnicQuestions,
                scrollController: controller,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

Future<void> _answers(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await _inApp(
    tester,
    world,
    (context) => Center(
      child: TextButton(
        onPressed: () => showEventAnswerSheet(
          context,
          eventTitle: 'Saturday hike',
          questions: picnicQuestions,
          initial: const {'note': 'Allergic to nuts'},
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

Future<void> _manage(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await _inApp(
    tester,
    world,
    (context) => Center(
      child: TextButton(
        onPressed: () => showEventManageSheet(
          context,
          kind: EventKind.chat,
          eventId: 'e-1',
          title: 'Saturday hike',
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

Future<void> _code(WidgetTester tester, PhoneWorld world) async {
  _fakes(world);
  await _inApp(
    tester,
    world,
    (context) => Center(
      child: TextButton(
        onPressed: () => showEventCheckInSheet(
          context,
          kind: EventKind.chat,
          eventId: 'e-1',
          title: 'Saturday hike',
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await settle(tester);
}

Future<void> _link(
  WidgetTester tester,
  PhoneWorld world, {
  bool fails = false,
}) async {
  final events2 = _fakes(world);
  if (fails) {
    events2.error = const EventException(EventFailure.codeInvalid);
  }
  await pumpStandalone(
    tester,
    world,
    const EventCheckInLinkScreen(code: 'abcd2345wxyz'),
  );
}

List<CircleEvent> _circleEvents() {
  return [
    circleEventWith(
      id: 'event-picnic',
      title: 'Club picnic with potluck and games on the lawn',
      extras: const EventExtras(
        coverPath: 'circle-1/events/picnic.jpg',
        recurrence: EventRecurrence.monthly,
        recurrenceTimeZone: 'America/New_York',
        questions: picnicQuestions,
        capacity: 4,
        waitlistCount: 3,
        photoCount: 2,
      ),
      startsAt: DateTime.now().add(const Duration(minutes: 45)),
    ),
    circleEventWith(
      id: 'event-signed-up',
      title: 'Board game night',
      extras: const EventExtras(capacity: 12),
      interested: 7,
      interestedByMe: true,
      startsAt: DateTime.now().add(const Duration(days: 2)),
    ),
    circleEventWith(
      id: 'event-wait',
      title: 'Sunrise run',
      extras: const EventExtras(
        capacity: 5,
        myWaitlisted: true,
        waitlistCount: 2,
      ),
      interested: 5,
      startsAt: DateTime.now().add(const Duration(minutes: 10)),
    ),
  ];
}

Future<void> _circleList(
  WidgetTester tester,
  PhoneWorld world, {
  String? first,
}) async {
  _fakes(world);
  // [first] leads the list, so its card is built without scrolling.
  world.circles.events = [
    for (final event in _circleEvents())
      if (event.id == first) event,
    for (final event in _circleEvents())
      if (event.id != first) event,
  ];
  await world.open(tester, '/circles/circle-1');
  await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
  await settle(tester);
}

Future<void> _circleDetail(
  WidgetTester tester,
  PhoneWorld world, {
  String event = 'event-picnic',
  bool menu = false,
}) async {
  await _circleList(tester, world, first: event);
  await tester.ensureVisible(find.byKey(ValueKey('circle-event-$event')));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('circle-event-$event')));
  await settle(tester);
  if (menu) {
    await tester.tap(find.byTooltip(tr('Event options')));
    await settle(tester);
  }
}

Future<void> _circleEditor(WidgetTester tester, PhoneWorld world) async {
  await _circleList(tester, world);
  await tester.tap(find.byKey(const ValueKey('circle-events-create')));
  await settle(tester);
  await tester.ensureVisible(
    find.byKey(const ValueKey('event-option-capacity')),
  );
  await settle(tester);
}

final events2A11yScreens = <A11yScreen>[
  A11yScreen('events2-card', (tester, world) => _chatCard(tester, world)),
  A11yScreen(
    'events2-card-large-text',
    (tester, world) => _chatCard(tester, world),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'events2-card-narrow',
    (tester, world) => _chatCard(tester, world),
    viewport: smallPhone,
  ),
  A11yScreen('events2-card-care-mode', (tester, world) async {
    _care(world);
    await _chatCard(tester, world);
  }),
  A11yScreen('events2-card-plain', (tester, world) async {
    await _chatCard(tester, world, extras: const EventExtras());
  }),
  A11yScreen('events2-sheet', (tester, world) => _chatSheet(tester, world)),
  A11yScreen(
    'events2-sheet-large-text',
    (tester, world) => _chatSheet(tester, world),
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'events2-sheet-narrow',
    (tester, world) => _chatSheet(tester, world),
    viewport: smallPhone,
  ),
  A11yScreen('events2-sheet-care-mode', (tester, world) async {
    _care(world);
    await _chatSheet(tester, world);
  }),
  A11yScreen('events2-sheet-waiting', (tester, world) async {
    await _chatSheet(
      tester,
      world,
      extras: const EventExtras(
        capacity: 3,
        waitlistCount: 2,
        myWaitlisted: true,
        recurrence: EventRecurrence.weekly,
      ),
    );
  }),
  A11yScreen('events2-sheet-checked-in', (tester, world) async {
    await _chatSheet(
      tester,
      world,
      myStatus: ChatEventRsvp.going,
      extras: const EventExtras(myCheckedIn: true, photoCount: 2),
    );
  }),
  A11yScreen('events2-editor', _chatEditor),
  A11yScreen(
    'events2-editor-large-text',
    _chatEditor,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('events2-editor-narrow', _chatEditor, viewport: smallPhone),
  A11yScreen('events2-questions-editor', _questionsEditor),
  A11yScreen(
    'events2-questions-editor-large-text',
    _questionsEditor,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'events2-questions-editor-narrow',
    _questionsEditor,
    viewport: smallPhone,
  ),
  A11yScreen('events2-answers', _answers),
  A11yScreen(
    'events2-answers-large-text',
    _answers,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('events2-answers-narrow', _answers, viewport: smallPhone),
  A11yScreen('events2-manage', _manage),
  A11yScreen(
    'events2-manage-large-text',
    _manage,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('events2-manage-narrow', _manage, viewport: smallPhone),
  A11yScreen('events2-manage-care-mode', (tester, world) async {
    _care(world);
    await _manage(tester, world);
  }),
  A11yScreen('events2-check-in-code', _code),
  A11yScreen(
    'events2-check-in-code-large-text',
    _code,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen('events2-check-in-code-narrow', _code, viewport: smallPhone),
  A11yScreen('events2-check-in-link', (tester, world) => _link(tester, world)),
  A11yScreen(
    'events2-check-in-link-failed',
    (tester, world) => _link(tester, world, fails: true),
    viewport: smallPhone,
  ),
  A11yScreen('events2-circle-list', (tester, world) async {
    await _circleList(tester, world);
  }),
  A11yScreen('events2-circle-list-large-text', (tester, world) async {
    await _circleList(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('events2-circle-list-narrow', (tester, world) async {
    await _circleList(tester, world);
  }, viewport: smallPhone),
  A11yScreen('events2-circle-list-care-mode', (tester, world) async {
    _care(world);
    await _circleList(tester, world);
  }),
  A11yScreen('events2-circle-detail', (tester, world) async {
    await _circleDetail(tester, world);
  }),
  A11yScreen('events2-circle-detail-large-text', (tester, world) async {
    await _circleDetail(tester, world);
  }, viewport: notchedPhoneLargeText),
  A11yScreen('events2-circle-detail-narrow', (tester, world) async {
    await _circleDetail(tester, world);
  }, viewport: smallPhone),
  A11yScreen('events2-circle-detail-waiting', (tester, world) async {
    await _circleDetail(tester, world, event: 'event-wait');
  }),
  A11yScreen('events2-circle-menu', (tester, world) async {
    await _circleDetail(tester, world, menu: true);
  }),
  A11yScreen('events2-circle-editor', _circleEditor),
  A11yScreen(
    'events2-circle-editor-large-text',
    _circleEditor,
    viewport: notchedPhoneLargeText,
  ),
  A11yScreen(
    'events2-circle-editor-narrow',
    _circleEditor,
    viewport: smallPhone,
  ),
  A11yScreen(
    'desktop-events2-circle-detail',
    (tester, world) async {
      await _circleDetail(tester, world);
    },
    viewport: desktopViewport,
    desktop: true,
  ),
];
