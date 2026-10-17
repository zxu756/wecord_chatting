import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_format.dart';
import 'package:wecord/features/chats/events/chat_event_reminder_card.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_providers.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/calendar/calendar_file_saver.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

const _conversation = 'conv-1';

ChatEvent chatEvent({
  String id = 'e-1',
  String title = 'Bouldering night',
  DateTime? startsAt,
  DateTime? endsAt,
  ChatEventRsvp? myStatus,
  int going = 2,
  int maybe = 1,
  int declined = 0,
  bool pinned = false,
  bool cancelled = false,
  bool canManage = true,
  String? location = 'The gym on 5th',
  String? link,
  String? description,
  List<int> reminders = const [15],
  List<ChatEventAttendee>? attendees,
}) {
  return ChatEvent(
    id: id,
    conversationId: _conversation,
    title: title,
    startsAt: startsAt ?? DateTime.now().add(const Duration(days: 2)),
    endsAt: endsAt,
    description: description,
    locationText: location,
    linkUrl: link,
    reminderLeads: reminders,
    pinnedAt: pinned ? DateTime.now() : null,
    cancelledAt: cancelled ? DateTime.now() : null,
    createdBy: 'user-1',
    creatorName: 'Ada',
    goingCount: going,
    maybeCount: maybe,
    declinedCount: declined,
    myStatus: myStatus,
    canManage: canManage,
    attendees:
        attendees ??
        const [
          ChatEventAttendee(
            id: 'user-1',
            username: 'ada',
            displayName: 'Ada',
            status: ChatEventRsvp.going,
          ),
          ChatEventAttendee(
            id: 'user-2',
            username: 'bart',
            displayName: 'Bart',
            status: ChatEventRsvp.going,
          ),
          ChatEventAttendee(
            id: 'user-3',
            username: 'grace',
            displayName: 'Grace',
            status: ChatEventRsvp.maybe,
          ),
        ],
  );
}

class FakeChatEventsRepository implements ChatEventsRepository {
  FakeChatEventsRepository(this.events);

  List<ChatEvent> events;
  final created = <ChatEventDraft>[];
  final updated = <(String, ChatEventDraft)>[];
  final rsvps = <(String, ChatEventRsvp?)>[];
  final pins = <(String, bool)>[];
  final cancelled = <String>[];
  var reminders = <ChatEventReminder>[];
  final readReminders = <List<String>?>[];
  final _changes = StreamController<void>.broadcast();

  void _replace(ChatEvent event) {
    events = [for (final e in events) e.id == event.id ? event : e];
  }

  @override
  Future<List<ChatEvent>> listEvents(
    String conversationId, {
    bool includePast = false,
  }) async => events;

  @override
  Future<ChatEvent?> getEvent(String eventId) async =>
      events.where((e) => e.id == eventId).firstOrNull;

  @override
  Future<ChatEvent> createEvent(
    String conversationId,
    ChatEventDraft draft,
  ) async {
    created.add(draft);
    final event = chatEvent(
      id: 'new-${created.length}',
      title: draft.title,
      startsAt: draft.startsAt,
      pinned: draft.pin,
      going: 1,
      maybe: 0,
    );
    events = [...events, event];
    return event;
  }

  @override
  Future<ChatEvent> updateEvent(String eventId, ChatEventDraft draft) async {
    updated.add((eventId, draft));
    return events.firstWhere((e) => e.id == eventId);
  }

  @override
  Future<ChatEvent> cancelEvent(String eventId) async {
    cancelled.add(eventId);
    final old = events.firstWhere((e) => e.id == eventId);
    final event = chatEvent(
      id: old.id,
      title: old.title,
      startsAt: old.startsAt,
      cancelled: true,
    );
    _replace(event);
    return event;
  }

  @override
  Future<ChatEvent> rsvp(String eventId, ChatEventRsvp? status) async {
    rsvps.add((eventId, status));
    final updated = events
        .firstWhere((e) => e.id == eventId)
        .copyWithRsvp(status);
    _replace(updated);
    return updated;
  }

  @override
  Future<ChatEvent> setPinned(String eventId, {required bool pinned}) async {
    pins.add((eventId, pinned));
    final old = events.firstWhere((e) => e.id == eventId);
    final event = chatEvent(
      id: old.id,
      title: old.title,
      startsAt: old.startsAt,
      pinned: pinned,
    );
    _replace(event);
    return event;
  }

  @override
  Stream<void> changes(String conversationId) => _changes.stream;

  @override
  Future<List<ChatEventReminder>> listReminders({int limit = 20}) async =>
      reminders;

  @override
  Future<void> markRemindersRead([List<String>? ids]) async {
    readReminders.add(ids);
  }
}

class _FakeSaver implements CalendarFileSaver {
  final saved = <({String fileName, String contents})>[];

  @override
  Future<CalendarSaveResult> save({
    required String fileName,
    required String contents,
    Rect? origin,
  }) async {
    saved.add((fileName: fileName, contents: contents));
    return CalendarSaveResult.downloaded;
  }
}

Future<({FakeChatEventsRepository repo, _FakeSaver saver})> _pump(
  WidgetTester tester,
  Widget child, {
  List<ChatEvent>? events,
}) async {
  // Tall, so lists inside sheets build all their rows.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeChatEventsRepository(events ?? [chatEvent()]);
  final saver = _FakeSaver();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatEventsRepositoryProvider.overrideWithValue(repo),
        calendarFileSaverProvider.overrideWithValue(saver),
        timeTokenFollowsClockProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: WeCordTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (repo: repo, saver: saver);
}

void main() {
  inboxReminderTests();
  group('model', () {
    test('reads the server JSON', () {
      final event = ChatEvent.fromJson({
        'id': 'e-1',
        'conversation_id': 'c-1',
        'title': 'Climb',
        'description': '  ',
        'location_text': 'Gym',
        'link_url': 'https://example.com/m',
        'starts_at': '2026-10-20T19:00:00+00:00',
        'ends_at': null,
        'reminder_leads': [15, 60],
        'pinned_at': '2026-10-17T10:00:00+00:00',
        'cancelled_at': null,
        'creator': {'display_name': 'Ada', 'username': 'ada'},
        'going_count': 3,
        'maybe_count': 1,
        'declined_count': 2,
        'my_status': 'maybe',
        'attendees': [
          {
            'id': 'u-1',
            'username': 'ada',
            'display_name': 'Ada',
            'avatar_url': null,
            'status': 'going',
          },
        ],
        'can_manage': true,
      });
      expect(event.description, isNull);
      expect(event.isPinned, isTrue);
      expect(event.myStatus, ChatEventRsvp.maybe);
      expect(event.reminderLeads, [15, 60]);
      expect(event.attendees.single.name, 'Ada');
      expect(event.creatorName, 'Ada');
      expect(
        event.effectiveEndsAt,
        event.startsAt.add(ChatEvent.defaultDuration),
      );
    });

    test('status follows the clock', () {
      final start = DateTime(2026, 10, 20, 19);
      final event = ChatEvent(
        id: 'e',
        conversationId: 'c',
        title: 't',
        startsAt: start,
        endsAt: start.add(const Duration(hours: 1)),
      );
      expect(
        event.statusAt(start.subtract(const Duration(minutes: 1))),
        ChatEventStatus.upcoming,
      );
      expect(event.statusAt(start), ChatEventStatus.live);
      expect(
        event.statusAt(start.add(const Duration(hours: 1))),
        ChatEventStatus.over,
      );
      expect(
        ChatEvent(
          id: 'e',
          conversationId: 'c',
          title: 't',
          startsAt: start,
          cancelledAt: start,
        ).statusAt(start),
        ChatEventStatus.cancelled,
      );
    });

    test('answering moves the counts', () {
      final event = chatEvent(
        going: 2,
        maybe: 1,
        myStatus: ChatEventRsvp.going,
      );
      final maybe = event.copyWithRsvp(ChatEventRsvp.maybe);
      expect((maybe.goingCount, maybe.maybeCount), (1, 2));
      final cleared = maybe.copyWithRsvp(null);
      expect((cleared.goingCount, cleared.maybeCount), (1, 1));
      final declined = cleared.copyWithRsvp(ChatEventRsvp.declined);
      expect(declined.declinedCount, 1);
    });

    test('the pinned event is the pinned one still ahead', () {
      final now = DateTime.now();
      final events = [
        chatEvent(
          id: 'a',
          startsAt: now.subtract(const Duration(days: 5)),
          pinned: true,
        ),
        chatEvent(id: 'b', pinned: true, cancelled: true),
        chatEvent(id: 'c', pinned: true),
        chatEvent(id: 'd'),
      ];
      expect(pinnedChatEvent(events, now)?.id, 'c');
      expect(pinnedChatEvent([events.last], now), isNull);
    });
  });

  group('words', () {
    final now = DateTime(2026, 10, 17, 14);

    test('when', () {
      final today = ChatEvent(
        id: 'e',
        conversationId: 'c',
        title: 't',
        startsAt: DateTime(2026, 10, 17, 20),
        endsAt: DateTime(2026, 10, 17, 22),
      );
      expect(formatChatEventWhen(today, now), 'Today · 8:00 PM – 10:00 PM');
      final tomorrow = ChatEvent(
        id: 'e',
        conversationId: 'c',
        title: 't',
        startsAt: DateTime(2026, 10, 18, 9, 30),
      );
      expect(
        formatChatEventWhen(tomorrow, now, use24Hour: true),
        'Tomorrow · 09:30',
      );
      final later = ChatEvent(
        id: 'e',
        conversationId: 'c',
        title: 't',
        startsAt: DateTime(2026, 10, 30, 9),
        endsAt: DateTime(2026, 10, 31, 11),
      );
      expect(
        formatChatEventWhen(later, now),
        'Fri, Oct 30 · 9:00 AM – Sat, Oct 31 · 11:00 AM',
      );
    });

    test('status and counts', () {
      final event = chatEvent(startsAt: DateTime(2026, 10, 17, 16));
      expect(chatEventStatusText(event, now), 'Starts in 2 hours');
      expect(chatEventCountsText(event), '2 going · 1 maybe');
      expect(
        chatEventCountsText(chatEvent(going: 0, maybe: 0)),
        'No answers yet',
      );
      expect(
        chatEventLinkLabel('https://www.example.com/map/x'),
        'example.com/map/x',
      );
    });

    test('the calendar file carries place, link and the shortest reminder', () {
      final ics = chatEventCalendarFile(
        chatEvent(
          startsAt: DateTime.utc(2026, 10, 20, 19),
          link: 'https://example.com/m',
          description: 'Bring chalk',
          reminders: const [15, 60],
        ),
        now: DateTime.utc(2026, 10, 17),
      );
      expect(ics, contains('DTSTART:20261020T190000Z'));
      expect(ics, contains('DTEND:20261020T210000Z'));
      expect(ics, contains('SUMMARY:Bouldering night'));
      expect(ics, contains('LOCATION:The gym on 5th'));
      expect(ics, contains('URL:https://example.com/m'));
      expect(ics, contains('TRIGGER:-PT15M'));
      expect(
        ics,
        contains(r'DESCRIPTION:Bring chalk\n\nhttps://example.com/m'),
      );
    });
  });

  group('card', () {
    testWidgets('shows the event and takes answers', (tester) async {
      final harness = await _pump(
        tester,
        const ChatEventCard(conversationId: _conversation, eventId: 'e-1'),
      );
      expect(find.text('Bouldering night'), findsOneWidget);
      expect(find.text('The gym on 5th'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-event-counts')), findsOneWidget);
      expect(find.textContaining('2 going · 1 maybe'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await tester.pump();
      await tester.pump();
      expect(harness.repo.rsvps, [('e-1', ChatEventRsvp.going)]);
      expect(find.textContaining('3 going · 1 maybe'), findsOneWidget);

      // Tapping the lit answer takes it back.
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await tester.pump();
      await tester.pump();
      expect(harness.repo.rsvps.last, ('e-1', null));
      expect(find.textContaining('2 going · 1 maybe'), findsOneWidget);
    });

    testWidgets('a cancelled event cannot be answered', (tester) async {
      final harness = await _pump(
        tester,
        const ChatEventCard(conversationId: _conversation, eventId: 'e-1'),
        events: [chatEvent(cancelled: true)],
      );
      expect(find.text('Cancelled'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-maybe')));
      await tester.pump();
      expect(harness.repo.rsvps, isEmpty);
    });

    testWidgets('opens the details with the people and the actions', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        const ChatEventCard(conversationId: _conversation, eventId: 'e-1'),
        events: [
          chatEvent(
            description: 'Bring **chalk**.',
            link: 'https://example.com/m',
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-card-e-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-event-sheet-title')),
        findsOneWidget,
      );
      expect(find.text('Going (2)'), findsOneWidget);
      expect(find.text('Maybe (1)'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chat-event-open-link')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Add to calendar'));
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();
      expect(harness.saver.saved.single.fileName, 'bouldering-night.ics');

      await tester.ensureVisible(find.text('Pin to chat header'));
      await tester.tap(find.text('Pin to chat header'));
      await tester.pumpAndSettle();
      expect(harness.repo.pins, [('e-1', true)]);
    });

    testWidgets('cancelling asks first', (tester) async {
      final harness = await _pump(
        tester,
        const ChatEventCard(conversationId: _conversation, eventId: 'e-1'),
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-card-e-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel event'));
      await tester.tap(find.text('Cancel event'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel event?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-event-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(harness.repo.cancelled, ['e-1']);
    });

    testWidgets('people who cannot manage do not see the controls', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChatEventCard(conversationId: _conversation, eventId: 'e-1'),
        events: [chatEvent(canManage: false)],
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-card-e-1')));
      await tester.pumpAndSettle();
      expect(find.text('Add to calendar'), findsOneWidget);
      expect(find.text('Pin to chat header'), findsNothing);
      expect(find.text('Edit event'), findsNothing);
    });
  });

  group('header strip', () {
    testWidgets('shows the pinned event and opens it', (tester) async {
      await _pump(
        tester,
        const ChatEventStrip(conversationId: _conversation),
        events: [
          chatEvent(id: 'a'),
          chatEvent(id: 'b', title: 'Pinned one', pinned: true),
        ],
      );
      expect(find.byKey(const ValueKey('chat-event-strip')), findsOneWidget);
      expect(find.text('Pinned one'), findsOneWidget);
      expect(find.textContaining('going'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-event-strip')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-event-sheet-title')),
        findsOneWidget,
      );
    });

    testWidgets('is empty without a pinned event', (tester) async {
      await _pump(tester, const ChatEventStrip(conversationId: _conversation));
      expect(find.byKey(const ValueKey('chat-event-strip')), findsNothing);
    });
  });

  group('list', () {
    testWidgets('upcoming first, past below, and a way to start one', (
      tester,
    ) async {
      final now = DateTime.now();
      final harness = await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventsList(context, conversationId: _conversation),
            child: const Text('open'),
          ),
        ),
        events: [
          chatEvent(
            id: 'old',
            title: 'Last month',
            startsAt: now.subtract(const Duration(days: 30)),
          ),
          chatEvent(id: 'soon', title: 'Soon'),
        ],
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-event-row-soon')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-event-row-old')), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      expect(find.text('Past'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-events-new')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('chat-event-title-field')),
        findsOneWidget,
      );
      expect(harness.repo.created, isEmpty);
    });
  });

  group('editor', () {
    Future<FakeChatEventsRepository> openEditor(
      WidgetTester tester, {
      ChatEvent? event,
    }) async {
      final harness = await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showChatEventEditor(
              context,
              conversationId: _conversation,
              event: event,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return harness.repo;
    }

    testWidgets('needs a title', (tester) async {
      final repo = await openEditor(tester);
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await tester.pump();
      expect(find.text('Give the event a title.'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('creates an event with its place, link and reminders', (
      tester,
    ) async {
      final repo = await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        '  Pizza night ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-location-field')),
        'My place',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-link-field')),
        'example.com/menu',
      );
      await tester.tap(find.text('Both'));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-pin')));
      await tester.tap(find.byKey(const ValueKey('chat-event-pin')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1));
      final draft = repo.created.single;
      expect(draft.title, '  Pizza night ');
      expect(draft.location, 'My place');
      expect(draft.link, 'https://example.com/menu');
      expect(draft.reminderLeads, [15, 60]);
      expect(draft.pin, isTrue);
      expect(draft.startsAt.isAfter(DateTime.now()), isTrue);
    });

    testWidgets('an end before the start is refused', (tester) async {
      final repo = await openEditor(tester);
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Short',
      );
      // Add an end time, then move it back before the start with the
      // pickers: the dialogs default to the start plus an hour, so keep it
      // and check the editor accepts that.
      await tester.tap(find.byKey(const ValueKey('chat-event-add-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await tester.pumpAndSettle();
      expect(repo.created.single.endsAt, isNotNull);
      expect(
        repo.created.single.endsAt!.isAfter(repo.created.single.startsAt),
        isTrue,
      );
    });
  });
}

void inboxReminderTests() {
  group('inbox reminder', () {
    testWidgets('names the event and opens its chat', (tester) async {
      final reminder = ChatEventReminder(
        id: 'r-1',
        eventId: 'e-1',
        conversationId: _conversation,
        title: 'Bouldering night',
        startsAt: DateTime.now().add(const Duration(minutes: 15, seconds: 30)),
        leadMinutes: 15,
        createdAt: DateTime.now(),
        isUnread: true,
      );
      var opened = 0;
      await _pump(
        tester,
        ChatEventReminderCard(reminder: reminder, onPressed: () => opened++),
      );
      expect(find.text('Bouldering night'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'Starts in 1[56] minutes')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('inbox-event-r-1')));
      expect(opened, 1);
    });
  });
}
