import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_row.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_widgets.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/features/events2/event_options_section.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/features/scheduled_calls/scheduled_calls.dart';
import 'package:wecord/features/voice/voice_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/zh/zh.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/shared/state/no_retry.dart';
import 'package:wecord/shared/ui/ui.dart' show WeCordSwitch;
import 'package:wecord/shared/theme/wecord_theme.dart';

import '../events2/events2_fakes.dart';
import '../voice/voice_fakes.dart';

const _code = 'abcdefghjk23';
const _callExtras = EventExtras(callLinkCode: _code);

/// An event that started [startedAgo] ago (or starts in [startsIn]), with a
/// call, lasting two hours as an event with no end does.
ChatEvent _event({
  Duration startedAgo = Duration.zero,
  Duration startsIn = Duration.zero,
  EventExtras extras = _callExtras,
  bool cancelled = false,
  DateTime? pinnedAt,
}) {
  final base = chatEventWith(extras: extras, cancelled: cancelled);
  return ChatEvent(
    id: base.id,
    conversationId: base.conversationId,
    title: 'Thursday sync',
    startsAt: DateTime.now().add(startsIn).subtract(startedAgo),
    locationText: base.locationText,
    createdBy: base.createdBy,
    creatorName: base.creatorName,
    goingCount: base.goingCount,
    maybeCount: base.maybeCount,
    canManage: true,
    cancelledAt: base.cancelledAt,
    pinnedAt: pinnedAt,
    attendees: base.attendees,
    extras: extras,
  );
}

class _Rig {
  _Rig(this.voice, this.connector, this.chat, this.events2);

  final FakeVoiceRepository voice;
  final FakeVoiceCallConnector connector;
  final FakeEventsChatRepository chat;
  final FakeEvents2Repository events2;
}

Future<_Rig> _pump(
  WidgetTester tester,
  Widget child, {
  required List<ChatEvent> events,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig(
    FakeVoiceRepository(),
    FakeVoiceCallConnector(),
    FakeEventsChatRepository(events),
    FakeEvents2Repository(),
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        chatEventsRepositoryProvider.overrideWithValue(rig.chat),
        events2RepositoryProvider.overrideWithValue(rig.events2),
        voiceRepositoryProvider.overrideWithValue(rig.voice),
        voiceCallConnectorProvider.overrideWithValue(rig.connector),
        authStateProvider.overrideWith(
          (ref) => Stream.value(const AuthUser(id: 'user-1')),
        ),
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

Future<void> _leave(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  await container.read(voiceSessionProvider.notifier).leave();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Finder _join(String id) => find.byKey(ValueKey('scheduled-call-join-$id'));

void main() {
  group('when the call can be joined', () {
    final start = DateTime(2026, 10, 22, 20);
    ChatEvent at({DateTime? ends, bool call = true, bool cancelled = false}) {
      return ChatEvent(
        id: 'e-1',
        conversationId: 'conv-1',
        title: 'Thursday sync',
        startsAt: start,
        endsAt: ends,
        cancelledAt: cancelled ? start : null,
        extras: call ? _callExtras : EventExtras.none,
      );
    }

    test('it opens 15 minutes before the start', () {
      final event = at();
      expect(
        ScheduledCall.phaseAt(event, start.subtract(const Duration(hours: 3))),
        ScheduledCallPhase.later,
      );
      expect(
        ScheduledCall.phaseAt(
          event,
          start.subtract(const Duration(minutes: 16)),
        ),
        ScheduledCallPhase.later,
      );
      expect(
        ScheduledCall.phaseAt(
          event,
          start.subtract(const Duration(minutes: 15)),
        ),
        ScheduledCallPhase.opening,
      );
      expect(
        ScheduledCall.phaseAt(
          event,
          start.subtract(const Duration(minutes: 1)),
        ),
        ScheduledCallPhase.opening,
      );
    });

    test('it is live from the start to the end', () {
      final event = at(ends: start.add(const Duration(minutes: 45)));
      expect(ScheduledCall.phaseAt(event, start), ScheduledCallPhase.live);
      expect(
        ScheduledCall.phaseAt(event, start.add(const Duration(minutes: 44))),
        ScheduledCallPhase.live,
      );
      expect(
        ScheduledCall.phaseAt(event, start.add(const Duration(minutes: 45))),
        ScheduledCallPhase.over,
      );
    });

    test('an event with no end lasts two hours', () {
      final event = at();
      expect(
        ScheduledCall.phaseAt(event, start.add(const Duration(minutes: 119))),
        ScheduledCallPhase.live,
      );
      expect(
        ScheduledCall.phaseAt(event, start.add(const Duration(hours: 2))),
        ScheduledCallPhase.over,
      );
    });

    test('no call, or a cancelled event, has none to join', () {
      expect(
        ScheduledCall.phaseAt(at(call: false), start),
        ScheduledCallPhase.none,
      );
      expect(
        ScheduledCall.phaseAt(at(cancelled: true), start),
        ScheduledCallPhase.none,
      );
      expect(ScheduledCall.canJoin(at(call: false), start), isFalse);
      expect(ScheduledCall.canJoin(at(), start), isTrue);
      expect(
        ScheduledCall.canJoin(at(), start.subtract(const Duration(hours: 1))),
        isFalse,
      );
    });

    test('the words follow the phase', () {
      expect(
        ScheduledCall.joinLabel(ScheduledCallPhase.live),
        'In progress · Join',
      );
      expect(
        ScheduledCall.joinLabel(ScheduledCallPhase.opening),
        'Join the call',
      );
    });
  });

  group('the model', () {
    test('reads the call link code', () {
      final extras = EventExtras.fromJson({'call_link_code': _code});
      expect(extras.callLinkCode, _code);
      expect(extras.hasCall, isTrue);
      expect(extras.isPlain, isFalse);
    });

    test('an event without a call reads as before', () {
      for (final json in [
        <String, dynamic>{},
        {'call_link_code': null},
        {'call_link_code': ''},
      ]) {
        final extras = EventExtras.fromJson(json);
        expect(extras.callLinkCode, isNull);
        expect(extras.hasCall, isFalse);
        expect(extras.isPlain, isTrue);
      }
    });

    test('a chat event holds whether it has a call; a circle event never', () {
      final chat = EventOptions.fromExtras(_callExtras, supportsCall: true);
      expect(chat.call, isTrue);
      expect(chat.toJson()['call'], isTrue);
      expect(
        EventOptions.fromExtras(
          EventExtras.none,
          supportsCall: true,
        ).toJson()['call'],
        isFalse,
      );
      final circle = EventOptions.fromExtras(EventExtras.none);
      expect(circle.call, isNull);
      expect(circle.toJson().containsKey('call'), isFalse);
    });

    test('options with a different call are different', () {
      expect(
        const EventOptions(call: true) == const EventOptions(call: false),
        isFalse,
      );
      expect(const EventOptions(call: true).copyWith(call: false).call, false);
    });
  });

  group('the card', () {
    testWidgets('says "In progress · Join" while the event is on', (
      tester,
    ) async {
      final event = _event(startedAgo: const Duration(minutes: 30));
      await _pump(
        tester,
        const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
        events: [event],
      );
      expect(_join('e-1'), findsOneWidget);
      expect(find.text('In progress · Join'), findsOneWidget);
      expect(find.text('Includes a call'), findsOneWidget);
    });

    testWidgets('says "Join the call" in the last minutes before', (
      tester,
    ) async {
      final event = _event(startsIn: const Duration(minutes: 8));
      await _pump(
        tester,
        const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
        events: [event],
      );
      expect(find.text('Join the call'), findsOneWidget);
      expect(find.text('In progress · Join'), findsNothing);
    });

    testWidgets('has no button before it opens, after it ends or when '
        'cancelled', (tester) async {
      for (final event in [
        _event(startsIn: const Duration(hours: 3)),
        _event(startedAgo: const Duration(hours: 3)),
        _event(startedAgo: const Duration(minutes: 5), cancelled: true),
        _event(
          startedAgo: const Duration(minutes: 5),
          extras: EventExtras.none,
        ),
      ]) {
        await _pump(
          tester,
          const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
          events: [event],
        );
        expect(_join('e-1'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('still shows that it includes a call before it opens', (
      tester,
    ) async {
      await _pump(
        tester,
        const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
        events: [_event(startsIn: const Duration(hours: 3))],
      );
      expect(find.text('Includes a call'), findsOneWidget);
    });

    testWidgets('joining starts the call in the chat of the event', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
        events: [_event(startedAgo: const Duration(minutes: 30))],
      );
      await tester.tap(_join('e-1'));
      await _settle(tester);
      expect(rig.voice.startedCalls, ['conv-1']);
      expect(rig.connector.calls, hasLength(1));
      // In the call, the button says so instead of joining again.
      expect(find.text('Open call'), findsOneWidget);
      await tester.tap(_join('e-1'));
      await _settle(tester);
      expect(rig.voice.startedCalls, ['conv-1']);
      await _leave(tester);
    });

    testWidgets('a refused call is explained and the button stays', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        const ChatEventCard(conversationId: 'conv-1', eventId: 'e-1'),
        events: [_event(startedAgo: const Duration(minutes: 30))],
      );
      rig.voice.startCallError = const VoiceAccessDeniedException();
      await tester.tap(_join('e-1'));
      await _settle(tester);
      expect(find.text("You can't call in this conversation."), findsOneWidget);
      expect(_join('e-1'), findsOneWidget);
      expect(rig.connector.calls, isEmpty);
    });

    testWidgets('the details sheet joins and closes', (tester) async {
      final rig = await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showChatEventSheet(context, 'e-1', 'conv-1'),
            child: const Text('open'),
          ),
        ),
        events: [_event(startedAgo: const Duration(minutes: 30))],
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      expect(_join('e-1'), findsOneWidget);
      await tester.tap(_join('e-1'));
      await _settle(tester);
      expect(rig.voice.startedCalls, ['conv-1']);
      expect(_join('e-1'), findsNothing);
      await _leave(tester);
    });

    testWidgets('the pinned strip has a short Join', (tester) async {
      final event = _event(
        startedAgo: const Duration(minutes: 30),
        pinnedAt: DateTime.now(),
      );
      final rig = await _pump(
        tester,
        const ChatEventStrip(conversationId: 'conv-1'),
        events: [event],
      );
      expect(find.text('Join'), findsOneWidget);
      await tester.tap(_join('e-1'));
      await _settle(tester);
      expect(rig.voice.startedCalls, ['conv-1']);
      await _leave(tester);
    });

    testWidgets('the pinned strip has none outside the call', (tester) async {
      await _pump(
        tester,
        const ChatEventStrip(conversationId: 'conv-1'),
        events: [
          _event(startsIn: const Duration(hours: 3), pinnedAt: DateTime.now()),
        ],
      );
      expect(find.byKey(const ValueKey('chat-event-strip')), findsOneWidget);
      expect(_join('e-1'), findsNothing);
    });
  });

  group('the form', () {
    testWidgets('has "Attach a call", off for an ordinary event', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        const SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: 'conv-1'),
        ),
        events: const [],
      );
      expect(find.text('Attach a call'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Lunch',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await _settle(tester);
      expect(rig.chat.created.single.options!.toJson()['call'], isFalse);
    });

    testWidgets('switching it on is sent with the event', (tester) async {
      final rig = await _pump(
        tester,
        const SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: 'conv-1'),
        ),
        events: const [],
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Stand-up',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('event-option-call')),
      );
      await tester.tap(find.byKey(const ValueKey('event-option-call')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await _settle(tester);
      expect(rig.chat.created.single.options!.toJson()['call'], isTrue);
    });

    testWidgets('"Schedule a call" starts with the call on', (tester) async {
      final rig = await _pump(
        tester,
        const SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: 'conv-1', scheduleCall: true),
        ),
        events: const [],
      );
      expect(find.text('Team call'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Design review',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await _settle(tester);
      expect(rig.chat.created.single.options!.toJson()['call'], isTrue);
    });

    testWidgets(
      'editing an event with a call shows it on and can take it off',
      (tester) async {
        final event = _event(startsIn: const Duration(days: 2));
        final rig = await _pump(
          tester,
          SizedBox(
            height: 2600,
            child: ChatEventEditor(conversationId: 'conv-1', event: event),
          ),
          events: [event],
        );
        final toggle = find.byKey(const ValueKey('event-option-call'));
        await tester.ensureVisible(toggle);
        expect(
          tester
              .widget<WeCordSwitch>(
                find.descendant(
                  of: toggle,
                  matching: find.byType(WeCordSwitch),
                ),
              )
              .value,
          isTrue,
        );
        await tester.tap(toggle);
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('chat-event-save')),
        );
        await tester.tap(find.byKey(const ValueKey('chat-event-save')));
        await _settle(tester);
        expect(rig.chat.updated.single.$2.options!.toJson()['call'], isFalse);
      },
    );

    testWidgets('an event is saved with a call kept when nothing changes', (
      tester,
    ) async {
      final event = _event(startsIn: const Duration(days: 2));
      final rig = await _pump(
        tester,
        SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: 'conv-1', event: event),
        ),
        events: [event],
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await _settle(tester);
      expect(rig.chat.updated.single.$2.options!.toJson()['call'], isTrue);
    });

    testWidgets('a chat where calls are not allowed says so', (tester) async {
      final rig = await _pump(
        tester,
        const SizedBox(
          height: 2600,
          child: ChatEventEditor(conversationId: 'conv-1', scheduleCall: true),
        ),
        events: const [],
      );
      rig.chat.createError = const PostgrestException(
        message: 'You cannot call in this conversation',
        code: '42501',
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-event-title-field')),
        'Call',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('chat-event-save')));
      await tester.tap(find.byKey(const ValueKey('chat-event-save')));
      await _settle(tester);
      expect(
        find.text(
          "You can't call in this chat, so the event can't have a call.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('the options section shows the row only where it can', (
      tester,
    ) async {
      final controller = EventOptionsController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        EventOptionsSection(
          controller: controller,
          kind: EventKind.circle,
          scopeId: 'circle-1',
        ),
        events: const [],
      );
      expect(find.byKey(const ValueKey('event-option-call')), findsNothing);
    });
  });

  group('the chat\'s More menu', () {
    HeaderActionContext contextFor(
      WidgetRef ref,
      BuildContext context, {
      required bool canCall,
      required bool canSend,
    }) {
      return HeaderActionContext(
        context: context,
        ref: ref,
        host: HeaderActionHost(
          toggleMessageSearch: () {},
          showPinnedMessages: (_) {},
          showGroupDetails: (_) {},
          setThreadArchived: (_, _) {},
          requestSummary: () {},
          openDisappearing: () {},
          openWallpaper: () {},
        ),
        conversationId: 'conv-1',
        title: 'Hike crew',
        conversationType: null,
        circleId: null,
        isNoteToSelf: false,
        isDirectOrGroup: true,
        canCall: canCall,
        canSend: canSend,
        canPinMessages: false,
        groupDetail: null,
        disappearingSeconds: null,
        threadId: null,
        canManageThread: false,
        threadArchived: false,
        forumPost: false,
        workspaceOpen: false,
        workspaceRequest: null,
        desktopChrome: false,
      );
    }

    testWidgets('has "Schedule a call" for chats that can call', (
      tester,
    ) async {
      ChatThreadAction? action;
      ChatThreadAction? blocked;
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            action = scheduleCallHeaderAction.build(
              contextFor(ref, context, canCall: true, canSend: true),
            );
            blocked = scheduleCallHeaderAction.build(
              contextFor(ref, context, canCall: true, canSend: false),
            );
            return const SizedBox();
          },
        ),
        events: const [],
      );
      expect(action, isNotNull);
      expect(action!.tooltip, 'Schedule a call');
      expect(action!.menuOnly, isTrue);
      expect(scheduleCallHeaderAction.order, greaterThan(2000));
      expect(blocked, isNull);
    });

    testWidgets('no action where calls do not apply', (tester) async {
      ChatThreadAction? action;
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            action = scheduleCallHeaderAction.build(
              contextFor(ref, context, canCall: false, canSend: true),
            );
            return const SizedBox();
          },
        ),
        events: const [],
      );
      expect(action, isNull);
    });
  });

  group('My agenda', () {
    AgendaItem item(Map<String, dynamic> meta) {
      return AgendaItem.tryParse({
        'kind': 'chat_event',
        'title': 'Thursday sync',
        'starts_at': '2026-10-22T18:00:00Z',
        'ends_at': '2026-10-22T19:00:00Z',
        'all_day': false,
        'conversation_id': 'conv-1',
        'target_id': 'e-1',
        'place_name': 'Hike crew',
        'meta': meta,
      })!;
    }

    test('reads the call link code out of the meta', () {
      expect(item({'status': 'going', 'call_link_code': _code}).hasCall, true);
      expect(item({'status': 'going'}).hasCall, isFalse);
      expect(item({'call_link_code': null}).hasCall, isFalse);
      expect(item({'call_link_code': ''}).callLinkCode, isNull);
    });

    testWidgets('a call reads as a scheduled call', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: WeCordTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                AgendaRow(
                  item: item({'status': 'going', 'call_link_code': _code}),
                  now: DateTime(2026, 10, 22),
                  onPressed: () {},
                ),
                AgendaRow(
                  item: item({'status': 'going'}),
                  now: DateTime(2026, 10, 22),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.textContaining('Scheduled call · '), findsOneWidget);
      expect(find.textContaining('Event · '), findsOneWidget);
      expect(find.byIcon(Icons.phone_in_talk_outlined), findsOneWidget);
    });
  });

  group('Chinese', () {
    test('the words are there', () {
      for (final text in [
        'Attach a call',
        'Includes a call',
        'In progress · Join',
        'Join the call',
        'Open call',
        'Schedule a call',
        'Scheduled call',
        'Team call',
      ]) {
        expect(zhStrings[text], isNotNull, reason: text);
      }
      expect(zhStrings['In progress · Join'], '正在进行 · 加入');
      expect(zhStrings['Schedule a call'], '预约通话');
    });
  });
}
