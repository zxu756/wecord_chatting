import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/circles/circle_events_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/features/events2/event_check_in.dart';
import 'package:wecord/features/events2/event_manage_sheet.dart';
import 'package:wecord/features/events2/event_options_section.dart';
import 'package:wecord/features/events2/event_photos_section.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/models/circle_event.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../../mobile/phone_test_support.dart';
import 'events2_fakes.dart';

class EventsRig {
  EventsRig(this.events2, this.chat, this.picker);

  final FakeEvents2Repository events2;
  final FakeEventsChatRepository chat;
  final FakeEventImagePicker picker;
}

class _CirclesStub extends Fake implements CirclesRepository {
  final calls = <String>[];

  @override
  Future<bool> toggleEventInterest(String eventId) async {
    calls.add('toggle $eventId');
    return true;
  }
}

Future<EventsRig> pump(
  WidgetTester tester,
  Widget child, {
  List<ChatEvent>? chatEvents,
  CirclesRepository? circles,
  void Function(FakeEvents2Repository events2)? setup,
}) async {
  // Tall, so lists inside sheets build all their rows.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = EventsRig(
    FakeEvents2Repository(),
    FakeEventsChatRepository(chatEvents ?? [chatEventWith()]),
    FakeEventImagePicker(),
  );
  setup?.call(rig.events2);
  await tester.pumpWidget(
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        events2RepositoryProvider.overrideWithValue(rig.events2),
        chatEventsRepositoryProvider.overrideWithValue(rig.chat),
        imagePickerServiceProvider.overrideWithValue(rig.picker),
        if (circles != null)
          circlesRepositoryProvider.overrideWithValue(circles),
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
  return rig;
}

Future<void> settleSheets(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

const _full = EventExtras(
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

void main() {
  group('the model', () {
    test('reads the Events 2.0 part of an event', () {
      final extras = EventExtras.fromJson({
        'cover_path': 'conv-1/events/cover.jpg',
        'recurrence': 'biweekly',
        'recurrence_tz': 'Europe/London',
        'series_id': 's-1',
        'questions': [
          {
            'id': 'meal',
            'label': 'Vegetarian?',
            'type': 'choice',
            'required': true,
            'options': ['Yes', 'No'],
          },
        ],
        'capacity': 12,
        'waitlist_count': 3,
        'my_waitlisted': true,
        'my_answers': {'meal': 'Yes'},
        'checked_in_count': 4,
        'my_checked_in': true,
        'photo_count': 7,
      });
      expect(extras.coverPath, 'conv-1/events/cover.jpg');
      expect(extras.recurrence, EventRecurrence.biweekly);
      expect(extras.recurrenceTimeZone, 'Europe/London');
      expect(extras.questions.single.type, EventQuestionType.choice);
      expect(extras.questions.single.required, isTrue);
      expect(extras.questions.single.options, ['Yes', 'No']);
      expect(extras.capacity, 12);
      expect(extras.waitlistCount, 3);
      expect(extras.myWaitlisted, isTrue);
      expect(extras.myAnswers, {'meal': 'Yes'});
      expect(extras.myCheckedIn, isTrue);
      expect(extras.photoCount, 7);
      expect(extras.isPlain, isFalse);
      expect(extras.isFull(12), isTrue);
      expect(extras.isFull(11), isFalse);
      expect(extras.seatsLeft(10), 2);
      expect(extras.seatsLeft(20), 0);
    });

    test('an event from an older server is plain', () {
      final extras = EventExtras.fromJson(const {'cover_path': ''});
      expect(extras.isPlain, isTrue);
      expect(extras.recurrence, EventRecurrence.none);
      expect(extras.capacity, isNull);
      expect(extras.isFull(1000), isFalse);
      expect(extras.seatsLeft(3), isNull);
    });

    test('chat and circle events carry it', () {
      final chat = ChatEvent.fromJson({
        'id': 'e-1',
        'conversation_id': 'c-1',
        'title': 'Climb',
        'starts_at': '2026-10-20T19:00:00+00:00',
        'capacity': 5,
        'recurrence': 'weekly',
      });
      expect(chat.extras.capacity, 5);
      expect(chat.extras.repeats, isTrue);
      expect(chat.copyWithRsvp(ChatEventRsvp.going).extras.capacity, 5);
      final circle = CircleEvent.fromJson({
        'id': 'e-2',
        'circle_id': 'c-1',
        'title': 'Picnic',
        'location_type': 'external',
        'location_text': 'Park',
        'starts_at': '2026-10-20T19:00:00+00:00',
        'capacity': 9,
        'my_waitlisted': true,
      });
      expect(circle.extras.capacity, 9);
      expect(circle.extras.myWaitlisted, isTrue);
      expect(circle.copyWith(interestedCount: 2).extras.capacity, 9);
    });

    test('options are sent with every key, and read back from an event', () {
      const options = EventOptions(
        recurrence: EventRecurrence.monthly,
        coverPath: 'conv-1/events/c.jpg',
        questions: [EventQuestion(id: 'q1', label: ' Meals? ')],
        capacity: 20,
        timeZone: 'Asia/Tokyo',
      );
      expect(options.toJson(), {
        'recurrence': 'monthly',
        'timezone': 'Asia/Tokyo',
        'cover_path': 'conv-1/events/c.jpg',
        'questions': [
          {'id': 'q1', 'label': 'Meals?', 'type': 'text', 'required': false},
        ],
        'capacity': 20,
      });
      const none = EventOptions();
      expect(none.toJson(), {
        'recurrence': null,
        'cover_path': null,
        'questions': <Object?>[],
        'capacity': null,
      });
      expect(EventOptions.fromExtras(_full).recurrence, EventRecurrence.weekly);
      expect(options.copyWith(capacity: null).capacity, isNull);
      expect(options.copyWith(coverPath: null).coverPath, isNull);
      expect(options.copyWith(recurrence: EventRecurrence.none).capacity, 20);
    });

    test('server errors become a reason people can read', () {
      expect(
        EventFailure.fromMessage('Please answer the required questions'),
        EventFailure.needsAnswers,
      );
      expect(
        EventFailure.fromMessage('Event is cancelled or over'),
        EventFailure.eventOver,
      );
      expect(
        EventFailure.fromMessage('This check-in code is not valid'),
        EventFailure.codeInvalid,
      );
      expect(
        EventFailure.fromMessage('Check-in has not opened yet'),
        EventFailure.checkInNotOpen,
      );
      expect(
        EventFailure.fromMessage('You are on the waiting list'),
        EventFailure.waitingList,
      );
      expect(
        EventFailure.fromMessage('You can add up to 20 pictures to an event'),
        EventFailure.photoLimit,
      );
      expect(
        EventFailure.fromMessage('Cannot manage this event'),
        EventFailure.notAllowed,
      );
      expect(EventFailure.fromMessage('boom'), EventFailure.other);
    });
  });

  group('check-in links', () {
    test('a QR link, a path and a browser address all mean check in', () {
      final url = checkInUrl(
        'abcd2345wxyz',
        site: 'https://wecord.jokebear.fyi',
      );
      expect(url, 'https://wecord.jokebear.fyi/checkin/abcd2345wxyz');
      expect(parseScannedText(url), const CheckInQrLink('abcd2345wxyz'));
      expect(
        parseScannedText('/checkin/ABCD2345WXYZ'),
        const CheckInQrLink('abcd2345wxyz'),
      );
      expect(
        parseScannedText('https://evil.example.com/checkin/abcd2345wxyz'),
        isA<OtherQrText>(),
      );
      expect(checkInLocationFor(Uri.parse(url)), '/checkin/abcd2345wxyz');
      expect(checkInLocationFor(Uri.parse('$url#/chats')), isNull);
      expect(
        checkInLocationFor(
          Uri.parse('https://wecord.jokebear.fyi/call/abcd2345wxyz'),
        ),
        isNull,
      );
      expect(isCheckInCode('abcd2345wxyz'), isTrue);
      expect(isCheckInCode('short'), isFalse);
    });

    test(
      'check-in opens two hours before the start and closes three after the end',
      () {
        final start = DateTime(2026, 10, 24, 10);
        final end = DateTime(2026, 10, 24, 12);
        bool at(DateTime now) =>
            eventCheckInOpen(startsAt: start, endsAt: end, now: now);
        expect(at(start.subtract(const Duration(hours: 3))), isFalse);
        expect(at(start.subtract(const Duration(hours: 2))), isTrue);
        expect(at(end.add(const Duration(hours: 2, minutes: 59))), isTrue);
        expect(at(end.add(const Duration(hours: 3))), isFalse);
      },
    );
  });

  group('the list for organisers', () {
    test('copies as a table with a column for each question', () {
      final table = eventRegistrationsTable(sampleRegistrations());
      final lines = table.split('\n');
      expect(
        lines.first,
        'Member,Response,Checked in,Vegetarian?,How many guests?,Anything we should know?',
      );
      expect(lines, hasLength(1 + 3 + 2 + 1));
      expect(lines[1], 'Ada Lovelace,going,Yes,Yes,2,');
      // Commas and quotes are escaped.
      expect(lines[2], startsWith('"Bart, the ""Bold""",going,,No,,'));
      expect(lines[5], 'Margaret,Waiting list,,,,');
      expect(lines.last, startsWith('Dennis,Walk-in,Yes'));
    });
  });

  group('the options of the form', () {
    Future<EventOptionsController> pumpSection(
      WidgetTester tester, {
      EventOptions? initial,
    }) async {
      final controller = EventOptionsController(initial);
      addTearDown(controller.dispose);
      await pump(
        tester,
        EventOptionsSection(
          controller: controller,
          kind: EventKind.chat,
          scopeId: eventsConversationId,
        ),
      );
      return controller;
    }

    testWidgets('start empty, with every row', (tester) async {
      await pumpSection(tester);
      expect(find.text('Does not repeat'), findsOneWidget);
      expect(find.text('No limit'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('event-option-questions')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('event-repeat-note')), findsNothing);
    });

    testWidgets('choose a repeat', (tester) async {
      final controller = await pumpSection(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-repeat')));
      await settleSheets(tester);
      expect(find.text('Every two weeks'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-repeat-biweekly')));
      await settleSheets(tester);
      expect(controller.recurrence, EventRecurrence.biweekly);
      expect(find.byKey(const ValueKey('event-repeat-note')), findsOneWidget);
      expect(controller.options.recurrence.wire, 'biweekly');
    });

    testWidgets('set the seats, refuse nonsense, take the limit off', (
      tester,
    ) async {
      final controller = await pumpSection(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-capacity')));
      await settleSheets(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-capacity-field')),
        '0',
      );
      await tester.tap(find.byKey(const ValueKey('event-capacity-save')));
      await settleSheets(tester);
      expect(find.text('Enter a number from 1 to 10000.'), findsOneWidget);
      expect(controller.capacity, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('event-capacity-field')),
        '12',
      );
      await tester.tap(find.byKey(const ValueKey('event-capacity-save')));
      await settleSheets(tester);
      expect(controller.capacity, 12);
      expect(find.text('12'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('event-option-capacity')));
      await settleSheets(tester);
      await tester.tap(find.text('No limit').last);
      await settleSheets(tester);
      expect(controller.capacity, isNull);
    });

    testWidgets('write a choice question', (tester) async {
      final controller = await pumpSection(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-questions')));
      await settleSheets(tester);

      // An empty question is refused.
      await tester.tap(find.byKey(const ValueKey('event-question-add')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('event-questions-done')));
      await tester.pump();
      expect(find.text('Every question needs some words.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('event-question-label-q1')),
        'Vegetarian?',
      );
      await tester.tap(find.text('Choice'));
      await tester.pump();
      // One option is too few.
      await tester.enterText(
        find.byKey(const ValueKey('event-question-options-q1')),
        'Yes',
      );
      await tester.tap(find.byKey(const ValueKey('event-questions-done')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('event-questions-error')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('event-question-options-q1')),
        'Yes\n\nNo\nYes',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('event-question-required-q1')),
      );
      await tester.tap(
        find.byKey(const ValueKey('event-question-required-q1')),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('event-questions-done')),
      );
      await tester.tap(find.byKey(const ValueKey('event-questions-done')));
      await settleSheets(tester);

      final question = controller.questions.single;
      expect(question.id, 'q1');
      expect(question.label, 'Vegetarian?');
      expect(question.type, EventQuestionType.choice);
      expect(question.required, isTrue);
      expect(question.options, ['Yes', 'No']);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('five questions at most', (tester) async {
      final controller = await pumpSection(
        tester,
        initial: EventOptions(
          questions: [
            for (var i = 1; i <= 5; i++)
              EventQuestion(id: 'q$i', label: 'Question $i'),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('event-option-questions')));
      await settleSheets(tester);
      expect(find.byKey(const ValueKey('event-question-add')), findsNothing);
      expect(find.text('An event can ask up to 5 questions.'), findsOneWidget);
      expect(controller.questions, hasLength(5));
    });

    testWidgets('add and remove a cover picture', (tester) async {
      final controller = EventOptionsController();
      addTearDown(controller.dispose);
      final rig = await pump(
        tester,
        EventOptionsSection(
          controller: controller,
          kind: EventKind.circle,
          scopeId: eventsCircleId,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('event-option-cover')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('cover circle circle-1'));
      expect(controller.coverPath, 'circle-1/events/cover-1.jpg');
      expect(find.text('Added'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove cover picture'));
      await tester.pump();
      expect(controller.coverPath, isNull);
    });

    testWidgets('a picture that does not upload says so', (tester) async {
      final controller = EventOptionsController();
      addTearDown(controller.dispose);
      final rig = await pump(
        tester,
        EventOptionsSection(
          controller: controller,
          kind: EventKind.chat,
          scopeId: eventsConversationId,
        ),
      );
      rig.events2.error = StateError('offline');
      await tester.tap(find.byKey(const ValueKey('event-option-cover')));
      await settleSheets(tester);
      expect(
        find.text("The picture didn't upload. Try again."),
        findsOneWidget,
      );
      expect(controller.coverPath, isNull);
    });
  });

  group('the questions when signing up', () {
    Future<void> ask(WidgetTester tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventAnswerSheet(
              context,
              eventTitle: 'Club picnic',
              questions: picnicQuestions,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
    }

    testWidgets('a required question has to be answered', (tester) async {
      await ask(tester);
      expect(find.text('Vegetarian? *'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await tester.pump();
      expect(find.text('This question needs an answer.'), findsOneWidget);
    });

    testWidgets('a number question takes a number', (tester) async {
      await ask(tester);
      await tester.tap(find.byKey(const ValueKey('event-answer-meal-Yes')));
      await tester.enterText(
        find.byKey(const ValueKey('event-answer-guests')),
        '1.2.3',
      );
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await tester.pump();
      expect(find.text('Enter a number.'), findsOneWidget);
    });

    testWidgets('answers come back without the empty ones', (tester) async {
      Map<String, String>? result;
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showEventAnswerSheet(
              context,
              eventTitle: 'Club picnic',
              questions: picnicQuestions,
              initial: const {'note': 'Hi'},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      expect(find.text('Hi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-answer-meal-No')));
      await tester.enterText(
        find.byKey(const ValueKey('event-answer-guests')),
        '2,5',
      );
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await settleSheets(tester);
      expect(result, {'meal': 'No', 'guests': '2.5', 'note': 'Hi'});
    });
  });

  group('a chat event', () {
    testWidgets('the card shows the cover, the repeat and the seats', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [chatEventWith(extras: _full, going: 3)],
      );
      expect(
        find.byKey(const ValueKey('event-cover-conv-1/events/cover.jpg')),
        findsOneWidget,
      );
      expect(find.text('Every week'), findsOneWidget);
      expect(find.text('Full · 3 of 3'), findsOneWidget);
      expect(find.text('2 on the waiting list'), findsOneWidget);
      expect(find.text('1 checked in'), findsOneWidget);
      // Full: Going becomes the waiting list.
      expect(find.text('Waitlist'), findsOneWidget);
    });

    testWidgets('a plain event looks as it did', (tester) async {
      await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
      );
      expect(find.byKey(const ValueKey('event-info-chips')), findsNothing);
      expect(find.text('Going'), findsOneWidget);
    });

    testWidgets('going with questions asks them first', (tester) async {
      final rig = await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [
          chatEventWith(
            extras: const EventExtras(questions: picnicQuestions, capacity: 10),
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await settleSheets(tester);
      expect(find.text('Vegetarian? *'), findsOneWidget);
      expect(rig.chat.rsvps, isEmpty);

      await tester.tap(find.byKey(const ValueKey('event-answer-meal-Yes')));
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await settleSheets(tester);
      expect(rig.events2.calls, ['rsvp-chat e-1 going']);
      expect(rig.events2.lastAnswers, {'meal': 'Yes'});
      expect(rig.chat.rsvps, isEmpty);
    });

    testWidgets('backing out of the questions answers nothing', (tester) async {
      final rig = await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [
          chatEventWith(extras: const EventExtras(questions: picnicQuestions)),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await settleSheets(tester);
      await tester.tap(find.text('Cancel'));
      await settleSheets(tester);
      expect(rig.events2.calls, isEmpty);
      expect(rig.chat.rsvps, isEmpty);
    });

    testWidgets('Maybe and Can\'t do not ask questions', (tester) async {
      final rig = await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [
          chatEventWith(extras: const EventExtras(questions: picnicQuestions)),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-maybe')));
      await settleSheets(tester);
      expect(rig.chat.rsvps, [('e-1', ChatEventRsvp.maybe)]);
    });

    testWidgets('on the waiting list, Going leaves it', (tester) async {
      final rig = await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [
          chatEventWith(
            extras: const EventExtras(capacity: 3, myWaitlisted: true),
          ),
        ],
      );
      expect(find.text('On waitlist'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await settleSheets(tester);
      expect(rig.chat.rsvps, [('e-1', null)]);
    });

    testWidgets('a refusal from the server is said in words', (tester) async {
      final rig = await pump(
        tester,
        const ChatEventCard(
          conversationId: eventsConversationId,
          eventId: 'e-1',
        ),
        chatEvents: [
          chatEventWith(extras: const EventExtras(questions: picnicQuestions)),
        ],
      );
      rig.events2.error = const EventException(EventFailure.eventOver);
      await tester.tap(find.byKey(const ValueKey('chat-event-rsvp-going')));
      await settleSheets(tester);
      await tester.tap(find.byKey(const ValueKey('event-answer-meal-Yes')));
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await settleSheets(tester);
      expect(find.text('This event is over or was cancelled.'), findsOneWidget);
    });

    testWidgets('the sheet has check-in, photos and the organiser\'s list', (
      tester,
    ) async {
      final rig = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventSheet(context, 'e-1', eventsConversationId),
            child: const Text('open'),
          ),
        ),
        chatEvents: [
          chatEventWith(
            extras: _full,
            startsAt: DateTime.now().add(const Duration(minutes: 30)),
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      expect(find.byKey(const ValueKey('event-check-in-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('event-photos')), findsOneWidget);
      expect(find.text('Sign-ups and check-in'), findsOneWidget);
      expect(
        find.text(
          'The event is full. You move up when someone drops out, and you get a notification.',
        ),
        findsNothing,
      );
      expect(rig.events2.calls, contains('photos chat e-1'));
    });

    testWidgets('checked in already shows a tick, not a scanner', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventSheet(context, 'e-1', eventsConversationId),
            child: const Text('open'),
          ),
        ),
        chatEvents: [
          chatEventWith(
            extras: const EventExtras(myCheckedIn: true),
            startsAt: DateTime.now().add(const Duration(minutes: 30)),
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      expect(find.byKey(const ValueKey('event-checked-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('event-check-in-scan')), findsNothing);
    });

    testWidgets('three days before the start there is no scanner', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventSheet(context, 'e-1', eventsConversationId),
            child: const Text('open'),
          ),
        ),
        chatEvents: [
          chatEventWith(
            extras: const EventExtras(),
            startsAt: DateTime.now().add(const Duration(days: 3)),
          ),
        ],
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      expect(find.byKey(const ValueKey('event-check-in-scan')), findsNothing);
      expect(find.byKey(const ValueKey('event-photos')), findsNothing);
    });

    testWidgets('a repeating event can be cancelled as a series', (
      tester,
    ) async {
      final rig = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventSheet(context, 'e-1', eventsConversationId),
            child: const Text('open'),
          ),
        ),
        chatEvents: [chatEventWith(extras: _full)],
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      await tester.scrollUntilVisible(
        find.text('Cancel event'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Cancel event').last);
      await settleSheets(tester);
      expect(
        find.byKey(const ValueKey('chat-event-confirm-cancel-series')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-event-confirm-cancel-series')),
      );
      await settleSheets(tester);
      expect(rig.events2.calls, contains('cancel-series chat e-1'));
      expect(rig.chat.cancelled, isEmpty);
    });

    testWidgets('one occurrence goes through the old cancel', (tester) async {
      final rig = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showChatEventSheet(context, 'e-1', eventsConversationId),
            child: const Text('open'),
          ),
        ),
        chatEvents: [chatEventWith(extras: _full)],
      );
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      await tester.scrollUntilVisible(
        find.text('Cancel event'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Cancel event').last);
      await settleSheets(tester);
      await tester.tap(find.byKey(const ValueKey('chat-event-confirm-cancel')));
      await settleSheets(tester);
      expect(rig.chat.cancelled, ['e-1']);
      expect(
        rig.events2.calls.where((c) => c.startsWith('cancel-series')),
        isEmpty,
      );
    });

    testWidgets('the editor sends the options it holds', (tester) async {
      final rig = await pump(
        tester,
        const SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: eventsConversationId),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Weekly standup',
      );
      await tester.tap(find.byKey(const ValueKey('event-option-repeat')));
      await settleSheets(tester);
      await tester.tap(find.byKey(const ValueKey('event-repeat-weekly')));
      await settleSheets(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-capacity')));
      await settleSheets(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-capacity-field')),
        '8',
      );
      await tester.tap(find.byKey(const ValueKey('event-capacity-save')));
      await settleSheets(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await settleSheets(tester);
      final options = rig.chat.created.single.options!.toJson();
      expect(options['recurrence'], 'weekly');
      expect(options['capacity'], 8);
      expect(options['questions'], isEmpty);
    });

    testWidgets('editing starts from what the event has', (tester) async {
      final rig = await pump(
        tester,
        SizedBox(
          height: 2600,
          child: ChatEventEditor(
            conversationId: eventsConversationId,
            event: chatEventWith(extras: _full),
          ),
        ),
        chatEvents: [chatEventWith(extras: _full)],
      );
      expect(find.text('Every week'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await settleSheets(tester);
      final options = rig.chat.updated.single.$2.options!.toJson();
      expect(options['recurrence'], 'weekly');
      expect(options['capacity'], 3);
      expect(options['cover_path'], 'conv-1/events/cover.jpg');
      expect((options['questions']! as List).length, 3);
    });
  });

  group('the organiser\'s list', () {
    Future<EventsRig> openManage(WidgetTester tester) async {
      final rig = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
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
      await settleSheets(tester);
      return rig;
    }

    testWidgets('lists everyone with their answers', (tester) async {
      await openManage(tester);
      final summary = tester.widget<Text>(
        find.byKey(const ValueKey('event-manage-summary')),
      );
      expect(
        summary.data,
        '3 signed up · 3 seats · 2 on the waiting list · 2 checked in',
      );
      expect(find.text('Ada Lovelace · Going'), findsOneWidget);
      expect(find.text('Vegetarian?: Yes'), findsWidgets);
      expect(
        find.text('Anything we should know?: Allergic to nuts'),
        findsOneWidget,
      );
      expect(find.text('Waiting list (2)'), findsOneWidget);
      expect(find.text('Walked in (1)'), findsOneWidget);
    });

    testWidgets('ticks people on and off', (tester) async {
      final rig = await openManage(tester);
      await tester.tap(find.byKey(const ValueKey('event-tick-user-2')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('tick user-2 true'));
      await tester.tap(find.byKey(const ValueKey('event-tick-user-1')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('tick user-1 false'));
    });

    testWidgets('copies the table', (tester) async {
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
      await openManage(tester);
      await tester.tap(find.byKey(const ValueKey('event-manage-copy')));
      await settleSheets(tester);
      expect(copied.single, startsWith('Member,Response,Checked in'));
      expect(find.text('The list was copied.'), findsOneWidget);
    });

    testWidgets('shows the check-in code as a QR code', (tester) async {
      final rig = await openManage(tester);
      await tester.tap(find.byKey(const ValueKey('event-manage-code')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('code chat e-1'));
      expect(find.byKey(const ValueKey('qr-card-code')), findsOneWidget);
      expect(find.text('Scan to check in'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-check-in-renew')));
      await settleSheets(tester);
      expect(
        rig.events2.calls.where((c) => c.startsWith('code chat')),
        hasLength(2),
      );
      expect(find.text('A new code was made.'), findsOneWidget);
    });

    testWidgets('says when the list cannot be loaded', (tester) async {
      final rig = await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventManageSheet(
              context,
              kind: EventKind.circle,
              eventId: 'e-1',
              title: 'Picnic',
            ),
            child: const Text('open'),
          ),
        ),
      );
      rig.events2.error = const EventException(EventFailure.notAllowed);
      await tester.tap(find.text('open'));
      await settleSheets(tester);
      expect(find.text('You cannot do that.'), findsOneWidget);
    });
  });

  group('checking in', () {
    testWidgets('the link page checks the person in', (tester) async {
      final rig = await pump(
        tester,
        const SizedBox(
          height: 600,
          child: EventCheckInLinkScreen(code: 'abcd2345wxyz'),
        ),
      );
      expect(rig.events2.calls, ['check-in abcd2345wxyz']);
      expect(find.text("You're checked in."), findsOneWidget);
      expect(find.text('Saturday hike'), findsOneWidget);
    });

    testWidgets('a code that does not work says so', (tester) async {
      final events2 = FakeEvents2Repository()
        ..error = const EventException(EventFailure.codeInvalid);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [events2RepositoryProvider.overrideWithValue(events2)],
          child: MaterialApp(
            theme: WeCordTheme.light(),
            home: const EventCheckInLinkScreen(code: 'abcd2345wxyz'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('This check-in code does not work. It may have expired.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('event-check-in-retry-link')),
        findsOneWidget,
      );
    });
  });

  group('the pictures of an event', () {
    testWidgets('show the album and add to it', (tester) async {
      final rig = await pump(
        tester,
        const EventPhotosSection(
          kind: EventKind.chat,
          eventId: 'e-1',
          scopeId: eventsConversationId,
          started: true,
          photoCount: 0,
        ),
      );
      expect(find.text('No pictures yet. Add the first one.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-photo-add')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('add-photo chat e-1'));
      expect(find.byKey(const ValueKey('event-photo-photo-1')), findsOneWidget);
      expect(find.text('Pictures (1)'), findsOneWidget);
    });

    testWidgets('open one and delete it', (tester) async {
      final rig = await pump(
        tester,
        const EventPhotosSection(
          kind: EventKind.circle,
          eventId: 'e-1',
          scopeId: eventsCircleId,
          started: true,
          photoCount: 1,
        ),
        setup: (events2) => events2.photos = const [
          EventPhoto(
            id: 'p1',
            bucket: 'chat-media',
            path: 'circle-1/events/a.jpg',
            userId: 'user-2',
            uploaderName: 'Bart',
            canDelete: true,
          ),
        ],
      );
      expect(find.text('Pictures (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-photo-p1')));
      await settleSheets(tester);
      expect(find.text('Added by Bart'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-photo-delete')));
      await settleSheets(tester);
      expect(rig.events2.calls, contains('delete-photo p1'));
      expect(find.text('No pictures yet. Add the first one.'), findsOneWidget);
    });

    testWidgets('are hidden before the event, unless there are some', (
      tester,
    ) async {
      await pump(
        tester,
        const EventPhotosSection(
          kind: EventKind.chat,
          eventId: 'e-1',
          scopeId: eventsConversationId,
          started: false,
          photoCount: 0,
        ),
      );
      expect(find.byKey(const ValueKey('event-photos')), findsNothing);
    });

    testWidgets('a full album says why', (tester) async {
      final rig = await pump(
        tester,
        const EventPhotosSection(
          kind: EventKind.chat,
          eventId: 'e-1',
          scopeId: eventsConversationId,
          started: true,
          photoCount: 0,
        ),
      );
      rig.events2.error = const EventException(EventFailure.photoLimit);
      await tester.tap(find.byKey(const ValueKey('event-photo-add')));
      await settleSheets(tester);
      expect(find.text('No more pictures can be added.'), findsOneWidget);
    });
  });

  group('a circle event', () {
    testWidgets('the card shows the seats and the button follows them', (
      tester,
    ) async {
      Future<void> show(CircleEvent event) async {
        await pump(
          tester,
          CircleEventCard(
            event: event,
            onTap: () {},
            onToggleInterest: () {},
            now: DateTime.now(),
          ),
        );
      }

      await show(circleEventWith(extras: _full, interested: 3));
      expect(find.text('Full · 3 of 3'), findsOneWidget);
      expect(find.text('Join waiting list'), findsOneWidget);

      await show(
        circleEventWith(
          extras: const EventExtras(capacity: 8, myWaitlisted: true),
        ),
      );
      expect(find.text('On the waiting list'), findsOneWidget);

      await show(
        circleEventWith(
          extras: const EventExtras(capacity: 8),
          interestedByMe: true,
        ),
      );
      expect(find.text('Signed up'), findsOneWidget);

      await show(circleEventWith(extras: const EventExtras(capacity: 8)));
      expect(find.text('Sign up'), findsOneWidget);

      // Without seats or questions it is the Interested of before.
      await show(circleEventWith());
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('signing up asks the questions; interest does not', (
      tester,
    ) async {
      final circles = _CirclesStub();
      late WidgetRef captured;
      var event = circleEventWith(
        extras: const EventExtras(questions: picnicQuestions),
      );
      final rig = await pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return TextButton(
              onPressed: () =>
                  toggleCircleEventInterest(context, captured, event),
              child: const Text('toggle'),
            );
          },
        ),
        circles: circles,
      );
      await tester.tap(find.text('toggle'));
      await settleSheets(tester);
      expect(find.text('Vegetarian? *'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-answer-meal-No')));
      await tester.tap(find.byKey(const ValueKey('event-answers-submit')));
      await settleSheets(tester);
      expect(rig.events2.calls, ['register event-picnic']);
      expect(rig.events2.lastAnswers, {'meal': 'No'});
      expect(circles.calls, isEmpty);

      // Already signed up: leaving needs no questions.
      event = circleEventWith(
        extras: const EventExtras(questions: picnicQuestions),
        interestedByMe: true,
      );
      await tester.tap(find.text('toggle'));
      await settleSheets(tester);
      expect(circles.calls, ['toggle event-picnic']);
    });
  });

  group('creating a circle event', () {
    testWidgets('sends the repeat, seats and questions', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final world = PhoneWorld();
      await world.open(tester, '/circles/circle-1');
      await tester.tap(find.byKey(const ValueKey('circle-events-entry')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('circle-events-create')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-title-field')),
        'Book club',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('event-option-repeat')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-repeat')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('event-repeat-monthly')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('event-option-capacity')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('event-capacity-field')),
        '15',
      );
      await tester.tap(find.byKey(const ValueKey('event-capacity-save')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('event-save')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('event-save')));
      await settle(tester);

      final options = world.circles.eventOptions.single!;
      expect(options['recurrence'], 'monthly');
      expect(options['capacity'], 15);
      expect(options['cover_path'], isNull);
      expect(options['questions'], isEmpty);
      // A circle event cannot carry a call (scheduled calls): nothing is sent.
      expect(options.containsKey('call'), isFalse);
      await world.close(tester);
    });
  });
}
